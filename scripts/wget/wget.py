#!/usr/bin/env python
import argparse
import email.utils
import json
import os
import signal
import sys
import threading
import time
from collections import deque
from datetime import timezone
from html.parser import HTMLParser
from urllib import parse, request

CHUNK_SIZE = 256 * 1024
DEFAULT_SEGMENT_SIZE = 5 * 1024 * 1024
DEFAULT_USER_AGENT = "wget_tool/1.0"
CANCEL_EVENT = threading.Event()


def read_tool_version(default="0.0.0"):
    path = os.path.join(os.path.dirname(__file__), "VERSION")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            value = handle.read().strip()
    except OSError:
        return default
    return value if value else default


TOOL_VERSION = read_tool_version()
try:
    from tool_version import TOOL_VERSION as _TOOL_VERSION
except Exception:
    _TOOL_VERSION = None
if _TOOL_VERSION:
    TOOL_VERSION = _TOOL_VERSION


class LinkExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attr_name = None
        if tag in ("a", "link"):
            attr_name = "href"
        elif tag in ("img", "script", "source", "video"):
            attr_name = "src"
        if not attr_name:
            return
        for name, value in attrs:
            if name == attr_name and value:
                self.links.append(value)


def parse_http_datetime(value):
    if not value:
        return None
    try:
        dt = email.utils.parsedate_to_datetime(value)
        if dt is None:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except Exception:
        return None


def update_mtime(path, mtime):
    if mtime is None:
        return
    try:
        os.utime(path, (mtime, mtime))
    except Exception:
        pass


def install_signal_handlers():
    def handle_sigint(_signum, _frame):
        CANCEL_EVENT.set()
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, handle_sigint)


def extract_links_from_file(file_path, base_url):
    try:
        with open(file_path, "rb") as handle:
            data = handle.read()
    except OSError:
        return []

    text = data.decode("utf-8", errors="replace")
    parser = LinkExtractor()
    try:
        parser.feed(text)
    except Exception:
        return []

    urls = []
    for link in parser.links:
        link = link.strip()
        if not link or link.startswith("#"):
            continue
        lowered = link.lower()
        if lowered.startswith(("javascript:", "mailto:", "data:")):
            continue
        absolute = parse.urljoin(base_url, link)
        absolute, _ = parse.urldefrag(absolute)
        parts = parse.urlsplit(absolute)
        if parts.scheme not in ("http", "https"):
            continue
        urls.append(absolute)
    return urls


def normalize_url(url):
    url, _ = parse.urldefrag(url)
    parts = parse.urlsplit(url)
    scheme = parts.scheme.lower()
    netloc = parts.netloc.lower()
    path = parts.path or "/"
    return parse.urlunsplit((scheme, netloc, path, parts.query, ""))


def same_host(url, host):
    return parse.urlsplit(url).netloc.lower() == host.lower()


def base_path_for_no_parent(url):
    parsed = parse.urlsplit(url)
    path = parsed.path or "/"
    if not path.endswith("/"):
        path = path.rsplit("/", 1)[0] + "/"
    if not path.startswith("/"):
        path = "/" + path
    return path


def path_within_base(url, base_path):
    path = parse.urlsplit(url).path or "/"
    return path.startswith(base_path)


def is_html_content(content_type, output_path):
    if content_type and "text/html" in content_type.lower():
        return True
    lower_path = output_path.lower()
    if lower_path.endswith((".html", ".htm")):
        return True
    return os.path.basename(lower_path) == "index.html"


def recursive_output_path(url, base_dir, suggested_name=None):
    parts = parse.urlsplit(url)
    path = parts.path or "/"
    if path.endswith("/"):
        leaf = suggested_name or "index.html"
        path = path + leaf
    path = parse.unquote(path.lstrip("/")).replace("/", os.sep)
    return os.path.join(base_dir, parts.netloc, path)


def temp_download_path(output_path):
    return output_path + ".par"


def parts_path_for(output_path):
    return output_path + ".parts"


def finalize_download(temp_path, final_path):
    if not os.path.exists(temp_path):
        return False
    os.replace(temp_path, final_path)
    return True


def load_parts(parts_path):
    try:
        with open(parts_path, "r", encoding="ascii") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    if "total_size" not in data or "ranges" not in data:
        return None
    if not isinstance(data["total_size"], int):
        return None
    if "segment_size" in data and not isinstance(data["segment_size"], int):
        return None
    if not isinstance(data["ranges"], list):
        return None
    ranges = []
    for item in data["ranges"]:
        if not isinstance(item, list) or len(item) != 3:
            return None
        start, end, done = item
        if not isinstance(start, int) or not isinstance(end, int):
            return None
        if start < 0 or end < start:
            return None
        ranges.append([start, end, bool(done)])
    data["ranges"] = ranges
    return data


def save_parts(parts_path, parts):
    temp_path = parts_path + ".tmp"
    with open(temp_path, "w", encoding="ascii") as handle:
        json.dump(parts, handle, separators=(",", ":"), sort_keys=True)
    os.replace(temp_path, parts_path)


def build_ranges(total_size, segment_size):
    segment_size = max(1, min(int(segment_size), total_size))
    ranges = []
    start = 0
    while start < total_size:
        end = min(total_size - 1, start + segment_size - 1)
        ranges.append((start, end))
        start = end + 1
    return ranges


def completed_bytes(parts):
    total = 0
    for start, end, done in parts["ranges"]:
        if done:
            total += end - start + 1
    return total


def find_parts_for_status(url, args):
    parts_paths = []
    base_dirs = []
    wanted_urls = set()
    wanted_urls.add(normalize_url(url))
    if url.endswith("/"):
        wanted_urls.add(normalize_url(url.rstrip("/")))
    else:
        wanted_urls.add(normalize_url(url + "/"))
    if args.output:
        output_is_dir = args.output.endswith(("/", "\\")) or os.path.isdir(args.output)
        if output_is_dir:
            base_dirs.append(args.output)
        else:
            final_path = args.output
            temp_path = temp_download_path(final_path)
            parts_path = parts_path_for(temp_path)
            if os.path.exists(parts_path):
                return parts_path
            base_dirs.append(os.path.dirname(final_path) or ".")
    else:
        base_dirs.append(args.directory)

    seen = set()
    for base_dir in base_dirs:
        if not base_dir:
            continue
        base_dir = normalize_path(base_dir)
        if base_dir in seen:
            continue
        seen.add(base_dir)
        if not os.path.isdir(base_dir):
            continue
        for root, _dirs, files in os.walk(base_dir):
            for name in files:
                if not name.endswith(".par.parts"):
                    continue
                candidate = os.path.join(root, name)
                parts = load_parts(candidate)
                if not parts:
                    continue
                parts_url = parts.get("url")
                if not parts_url:
                    continue
                parts_norm = normalize_url(parts_url)
                if parts_norm in wanted_urls:
                    parts_paths.append(candidate)
                    continue
                if parts_url.endswith("/"):
                    alt = normalize_url(parts_url.rstrip("/"))
                else:
                    alt = normalize_url(parts_url + "/")
                if alt in wanted_urls:
                    parts_paths.append(candidate)

    if parts_paths:
        parts_paths.sort()
        return parts_paths[0]
    return None


def report_status(url, args):
    parts_path = find_parts_for_status(url, args)
    if not parts_path:
        print(f"No .par.parts found for {url}")
        return False

    parts = load_parts(parts_path)
    if not parts:
        print(f"Failed to read {parts_path}")
        return False

    total_size = parts.get("total_size")
    completed = completed_bytes(parts)
    total_ranges = len(parts["ranges"])
    done_ranges = sum(1 for item in parts["ranges"] if item[2])
    percent = (completed / total_size * 100) if total_size else 0.0
    segment_size = parts.get("segment_size")
    if segment_size is None and parts["ranges"]:
        segment_size = parts["ranges"][0][1] - parts["ranges"][0][0] + 1

    temp_path = parts_path[:-6] if parts_path.endswith(".parts") else ""
    final_path = temp_path[:-4] if temp_path.endswith(".par") else ""

    print(f"Status: {parts_path}")
    print(f"URL: {parts.get('url', url)}")
    print(
        f"Completed: {format_size(completed)}/{format_size(total_size)} ({percent:.2f}%)"
    )
    print(f"Ranges: {done_ranges}/{total_ranges}")
    if segment_size:
        print(f"Segment size: {format_size(segment_size)}")
    if temp_path:
        print(f"Partial file: {temp_path}")
    if final_path:
        print(f"Final file: {final_path}")
    return True


def enqueue_links(queue, output_path, base_url, depth, ctx, args, content_type):
    if depth >= args.max_depth:
        return
    if not is_html_content(content_type, output_path):
        return
    links = extract_links_from_file(output_path, base_url)
    for link in links:
        if not same_host(link, ctx["host"]):
            continue
        if args.no_parent and not path_within_base(link, ctx["base_path"]):
            continue
        queue.append((link, depth + 1, ctx))


def parse_headers(header_list):
    headers = {}
    for item in header_list:
        if ":" not in item:
            raise ValueError(f"Invalid header format: {item}")
        name, value = item.split(":", 1)
        name = name.strip()
        value = value.strip()
        if not name:
            raise ValueError(f"Invalid header name: {item}")
        headers[name] = value
    return headers


def parse_size(value):
    if value is None:
        return None
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if not text:
        raise ValueError("Invalid size value")
    if text.isdigit():
        return int(text)

    number = []
    unit = []
    for char in text:
        if char.isdigit() or char == ".":
            number.append(char)
        elif char.isalpha():
            unit.append(char)
        elif char in (" ", "_"):
            continue
        else:
            raise ValueError(f"Invalid size value: {value}")
    if not number:
        raise ValueError(f"Invalid size value: {value}")

    unit_text = "".join(unit).lower()
    if unit_text.endswith("b") and unit_text not in ("kb", "mb", "gb"):
        unit_text = unit_text[:-1]
    multipliers = {
        "k": 1024,
        "kb": 1024,
        "m": 1024 * 1024,
        "mb": 1024 * 1024,
        "g": 1024 * 1024 * 1024,
        "gb": 1024 * 1024 * 1024,
    }
    if unit_text not in multipliers:
        raise ValueError(f"Invalid size unit: {value}")
    return int(float("".join(number)) * multipliers[unit_text])


def format_size(num_bytes):
    if num_bytes is None:
        return "?"
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(num_bytes)
    for unit in units:
        if size < 1024.0 or unit == units[-1]:
            return f"{size:.2f}{unit}"
        size /= 1024.0
    return f"{size:.2f}TB"


def normalize_path(path):
    if not path:
        return ""
    return os.path.abspath(path)


def format_eta(seconds):
    if seconds is None:
        return "?"
    seconds = int(seconds)
    if seconds < 0:
        seconds = 0
    minutes, sec = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{sec:02d}"
    return f"{minutes:02d}:{sec:02d}"


def progress_line(downloaded, total_size, start_time, thread_info=None):
    elapsed = max(time.time() - start_time, 0.001)
    rate = downloaded / elapsed
    thread_text = ""
    if thread_info:
        thread_text = f" T{thread_info}"
    if total_size:
        pct = (downloaded / total_size) * 100
        remaining = max(total_size - downloaded, 0)
        eta = remaining / rate if rate > 0 else None
        return (
            f"{pct:6.2f}%{thread_text} {format_size(downloaded)}/{format_size(total_size)} "
            f"{format_size(rate)}/s ETA {format_eta(eta)}"
        )
    return f"{thread_text} {format_size(downloaded)} {format_size(rate)}/s"


def progress_worker(progress, total_size, stop_event, quiet):
    while not stop_event.is_set():
        if not quiet:
            line = progress_line(
                progress["downloaded"],
                total_size,
                progress["start"],
                progress.get("threads"),
            )
            sys.stdout.write("\r" + line)
            sys.stdout.flush()
        stop_event.wait(0.5)


def safe_filename_from_url(url):
    parsed = parse.urlsplit(url)
    name = os.path.basename(parsed.path)
    if not name or name in (".", ".."):
        return "index.html"
    return parse.unquote(name)


def parse_content_length(value):
    if not value:
        return None
    value = value.strip()
    if value.isdigit():
        return int(value)
    return None


def parse_content_range(value):
    if not value:
        return None
    value = value.strip()
    if "/" not in value:
        return None
    total = value.split("/", 1)[1]
    if total.isdigit():
        return int(total)
    return None


def filename_from_content_disposition(value):
    if not value:
        return None
    parts = [part.strip() for part in value.split(";") if part.strip()]
    if len(parts) < 2:
        return None
    params = {}
    for part in parts[1:]:
        if "=" not in part:
            continue
        key, val = part.split("=", 1)
        key = key.strip().lower()
        val = val.strip()
        if val.startswith("\"") and val.endswith("\""):
            val = val[1:-1]
        params[key] = val
    if "filename*" in params:
        value = params["filename*"]
        if "''" in value:
            _, _, encoded = value.partition("''")
            return os.path.basename(parse.unquote(encoded))
        return os.path.basename(parse.unquote(value))
    if "filename" in params:
        return os.path.basename(params["filename"])
    return None


def fetch_info(url, headers, timeout, max_tries):
    final_url = url
    total_size = None
    supports_range = False
    content_type = None
    last_modified = None
    content_disposition = None

    for attempt in range(max_tries):
        try:
            req = request.Request(url, headers=headers, method="HEAD")
            with request.urlopen(req, timeout=timeout * (attempt + 1)) as resp:
                final_url = resp.geturl()
                total_size = parse_content_length(resp.headers.get("Content-Length"))
                accept_ranges = resp.headers.get("Accept-Ranges") or ""
                supports_range = accept_ranges.lower() == "bytes"
                content_type = resp.headers.get("Content-Type")
                last_modified = resp.headers.get("Last-Modified")
                content_disposition = resp.headers.get("Content-Disposition")
            break
        except Exception:
            if attempt >= max_tries - 1:
                pass
            time.sleep(1)

    if (
        total_size is None
        or not supports_range
        or content_type is None
        or last_modified is None
        or content_disposition is None
    ):
        range_headers = dict(headers)
        range_headers["Range"] = "bytes=0-0"
        for attempt in range(max_tries):
            try:
                req = request.Request(url, headers=range_headers)
                with request.urlopen(req, timeout=timeout * (attempt + 1)) as resp:
                    final_url = resp.geturl()
                    status = getattr(resp, "status", None)
                    content_range = resp.headers.get("Content-Range")
                    if content_range:
                        total_size = parse_content_range(content_range)
                        supports_range = True
                    elif status == 206:
                        supports_range = True
                    elif total_size is None:
                        total_size = parse_content_length(
                            resp.headers.get("Content-Length")
                        )
                    if content_type is None:
                        content_type = resp.headers.get("Content-Type")
                    if last_modified is None:
                        last_modified = resp.headers.get("Last-Modified")
                    if content_disposition is None:
                        content_disposition = resp.headers.get("Content-Disposition")
                break
            except Exception:
                if attempt >= max_tries - 1:
                    pass
                time.sleep(1)

    return (
        final_url,
        total_size,
        supports_range,
        content_type,
        last_modified,
        content_disposition,
    )


def ensure_directory(path):
    if path and not os.path.exists(path):
        os.makedirs(path, exist_ok=True)


def download_single(
    url,
    output_path,
    headers,
    timeout,
    resume_from,
    total_size,
    quiet,
    max_tries,
    cancel_event=None,
    thread_label=None,
):
    progress = {"downloaded": resume_from, "start": time.time(), "threads": thread_label}
    stop_event = threading.Event()
    thread = threading.Thread(
        target=progress_worker,
        args=(progress, total_size, stop_event, quiet),
        daemon=True,
    )
    thread.start()

    try:
        for attempt in range(max_tries):
            try:
                if cancel_event and cancel_event.is_set():
                    return False
                req = request.Request(url, headers=headers)
                if resume_from:
                    req.add_header("Range", f"bytes={resume_from}-")
                with request.urlopen(req, timeout=timeout * (attempt + 1)) as resp:
                    status = getattr(resp, "status", None)
                    mode = "ab" if resume_from else "wb"
                    if resume_from and status == 200:
                        resume_from = 0
                        progress["downloaded"] = 0
                        mode = "wb"
                    with open(output_path, mode) as out_file:
                        while True:
                            if cancel_event and cancel_event.is_set():
                                return False
                            chunk = resp.read(CHUNK_SIZE)
                            if not chunk:
                                break
                            out_file.write(chunk)
                            progress["downloaded"] += len(chunk)
                return True
            except Exception:
                if attempt >= max_tries - 1:
                    raise
                time.sleep(1)
        return False
    finally:
        stop_event.set()
        thread.join()
        if not quiet:
            line = progress_line(progress["downloaded"], total_size, progress["start"])
            sys.stdout.write("\r" + line + "\n")
            sys.stdout.flush()


def download_range(
    url,
    output_path,
    headers,
    timeout,
    range_index,
    start,
    end,
    progress,
    lock,
    max_tries,
    errors,
    parts,
    parts_path,
    cancel_event=None,
):
    range_header = f"bytes={start}-{end}"
    for attempt in range(max_tries):
        if cancel_event and cancel_event.is_set():
            return False
        try:
            req = request.Request(url, headers=headers)
            req.add_header("Range", range_header)
            with request.urlopen(req, timeout=timeout * (attempt + 1)) as resp:
                status = getattr(resp, "status", None)
                if status == 200 and start != 0:
                    raise RuntimeError("Server did not honor range requests")
                with open(output_path, "r+b") as out_file:
                    out_file.seek(start)
                    while True:
                        if cancel_event and cancel_event.is_set():
                            return False
                        chunk = resp.read(CHUNK_SIZE)
                        if not chunk:
                            break
                        out_file.write(chunk)
                        with lock:
                            progress["downloaded"] += len(chunk)
            with lock:
                if parts is not None and parts_path is not None:
                    parts["ranges"][range_index][2] = True
                    save_parts(parts_path, parts)
            return True
        except Exception as exc:
            if attempt >= max_tries - 1:
                with lock:
                    errors.append(exc)
                return False
            time.sleep(1)
    return False


def range_worker(
    queue,
    queue_lock,
    url,
    output_path,
    headers,
    timeout,
    progress,
    lock,
    max_tries,
    errors,
    parts,
    parts_path,
    window_stop_event=None,
    cancel_event=None,
):
    while True:
        if cancel_event and cancel_event.is_set():
            return
        if window_stop_event and window_stop_event.is_set():
            return
        with queue_lock:
            if not queue:
                return
            range_index, start, end = queue.popleft()
        download_range(
            url,
            output_path,
            headers,
            timeout,
            range_index,
            start,
            end,
            progress,
            lock,
            max_tries,
            errors,
            parts,
            parts_path,
            cancel_event,
        )


def download_multi(
    url,
    output_path,
    headers,
    timeout,
    total_size,
    threads,
    quiet,
    max_tries,
    resume=False,
    segment_size=DEFAULT_SEGMENT_SIZE,
    auto_threads=False,
    min_threads=1,
    max_threads=64,
    auto_window=30.0,
    auto_min_gain=0.05,
):
    threads = max(1, min(threads, total_size))
    if total_size == 0:
        with open(output_path, "wb"):
            pass
        return True

    parts_path = parts_path_for(output_path)
    parts = None
    if resume and os.path.exists(parts_path):
        parts = load_parts(parts_path)
        if parts and parts.get("total_size") != total_size:
            parts = None
            if not quiet:
                print("Partial metadata mismatched; restarting download.")
        if parts and "segment_size" in parts:
            segment_size = parts["segment_size"]
        elif parts:
            if parts["ranges"]:
                segment_size = parts["ranges"][0][1] - parts["ranges"][0][0] + 1
            parts["segment_size"] = segment_size
            save_parts(parts_path, parts)

    if parts is None:
        ranges = build_ranges(total_size, segment_size)
        parts = {
            "url": url,
            "total_size": total_size,
            "segment_size": segment_size,
            "ranges": [[start, end, False] for start, end in ranges],
        }
        save_parts(parts_path, parts)

    pending = [
        (index, start, end)
        for index, (start, end, done) in enumerate(parts["ranges"])
        if not done
    ]
    if not pending:
        if not quiet:
            print(f"Skipping {output_path}; already complete.")
        if os.path.exists(parts_path):
            os.remove(parts_path)
        return True

    progress = {
        "downloaded": completed_bytes(parts),
        "start": time.time(),
        "threads": threads,
    }
    lock = threading.Lock()
    queue_lock = threading.Lock()
    stop_event = threading.Event()
    errors = []
    cancel_event = CANCEL_EVENT
    thread = threading.Thread(
        target=progress_worker,
        args=(progress, total_size, stop_event, quiet),
        daemon=True,
    )
    thread.start()

    try:
        if not os.path.exists(output_path):
            with open(output_path, "wb") as out_file:
                out_file.truncate(total_size)
        else:
            current_size = os.path.getsize(output_path)
            if current_size < total_size:
                with open(output_path, "ab") as out_file:
                    out_file.truncate(total_size)
            elif current_size > total_size:
                with open(output_path, "wb") as out_file:
                    out_file.truncate(total_size)
                for item in parts["ranges"]:
                    item[2] = False
                save_parts(parts_path, parts)
                pending = [
                    (index, start, end)
                    for index, (start, end, done) in enumerate(parts["ranges"])
                    if not done
                ]

        queue = deque(pending)
        if auto_threads:
            min_threads = max(1, int(min_threads))
            max_threads = max(min_threads, int(max_threads))
            current_threads = min(max_threads, max(min_threads, int(threads)))
            baseline_threads = current_threads
            baseline_rate = None
            progress["threads"] = current_threads

            while True:
                if cancel_event.is_set():
                    break
                with queue_lock:
                    if not queue:
                        break

                start_bytes = progress["downloaded"]
                start_time = time.time()
                start_errors = len(errors)
                window_stop_event = threading.Event()
                with queue_lock:
                    queue_size = len(queue)
                if queue_size == 0:
                    break
                worker_count = min(current_threads, queue_size)
                progress["threads"] = worker_count
                workers = []
                for _ in range(worker_count):
                    worker = threading.Thread(
                        target=range_worker,
                        args=(
                            queue,
                            queue_lock,
                            url,
                            output_path,
                            headers,
                            timeout,
                            progress,
                            lock,
                            max_tries,
                            errors,
                            parts,
                            parts_path,
                            window_stop_event,
                            cancel_event,
                        ),
                        daemon=True,
                    )
                    worker.start()
                    workers.append(worker)

                while True:
                    if cancel_event.is_set():
                        break
                    elapsed = time.time() - start_time
                    if elapsed >= auto_window:
                        break
                    with queue_lock:
                        if not queue:
                            break
                    time.sleep(0.2)

                window_stop_event.set()
                for worker in workers:
                    while worker.is_alive():
                        worker.join(timeout=0.2)
                        if cancel_event.is_set():
                            break
                    if cancel_event.is_set():
                        break

                elapsed = max(time.time() - start_time, 0.001)
                bytes_delta = progress["downloaded"] - start_bytes
                rate = bytes_delta / elapsed
                errors_delta = len(errors) - start_errors

                with queue_lock:
                    queue_empty = not queue

                if errors_delta > 0:
                    if baseline_threads > min_threads:
                        baseline_threads -= 1
                        if not quiet:
                            print(
                                f"Auto-threads: errors; reducing to {baseline_threads}"
                            )
                    current_threads = baseline_threads
                    progress["threads"] = current_threads
                    if queue_empty:
                        break
                    continue

                if baseline_rate is None:
                    baseline_rate = rate
                    baseline_threads = current_threads
                    if baseline_threads < max_threads:
                        current_threads = baseline_threads + 1
                        if not quiet:
                            print(f"Auto-threads: probing {current_threads}")
                        progress["threads"] = current_threads
                    if queue_empty:
                        break
                    continue

                if current_threads == baseline_threads:
                    if baseline_threads < max_threads:
                        current_threads = baseline_threads + 1
                        if not quiet:
                            print(f"Auto-threads: probing {current_threads}")
                        progress["threads"] = current_threads
                    elif baseline_threads > min_threads:
                        current_threads = baseline_threads - 1
                        if not quiet:
                            print(f"Auto-threads: probing {current_threads}")
                        progress["threads"] = current_threads
                    if queue_empty:
                        break
                    continue

                if baseline_rate <= 0:
                    improved = rate > 0
                else:
                    improved = rate >= baseline_rate * (1.0 + auto_min_gain)
                if improved:
                    baseline_threads = current_threads
                    baseline_rate = rate
                    if baseline_threads < max_threads:
                        current_threads = baseline_threads + 1
                        if not quiet:
                            print(f"Auto-threads: increasing to {current_threads}")
                        progress["threads"] = current_threads
                    else:
                        current_threads = baseline_threads
                else:
                    if current_threads > baseline_threads:
                        if baseline_threads > min_threads:
                            current_threads = baseline_threads - 1
                            if not quiet:
                                print(f"Auto-threads: probing {current_threads}")
                            progress["threads"] = current_threads
                        else:
                            current_threads = baseline_threads
                    else:
                        current_threads = baseline_threads

                if queue_empty:
                    break
        else:
            worker_count = min(threads, len(pending))
            progress["threads"] = worker_count
            workers = []
            for _ in range(worker_count):
                worker = threading.Thread(
                    target=range_worker,
                    args=(
                        queue,
                        queue_lock,
                        url,
                        output_path,
                        headers,
                        timeout,
                        progress,
                        lock,
                        max_tries,
                        errors,
                        parts,
                        parts_path,
                        None,
                        cancel_event,
                    ),
                    daemon=True,
                )
                worker.start()
                workers.append(worker)

            for worker in workers:
                while worker.is_alive():
                    worker.join(timeout=0.2)
                    if cancel_event.is_set():
                        break
                if cancel_event.is_set():
                    break

        if not errors and not cancel_event.is_set() and os.path.exists(parts_path):
            os.remove(parts_path)
    finally:
        stop_event.set()
        thread.join()
        if not quiet:
            line = progress_line(progress["downloaded"], total_size, progress["start"])
            sys.stdout.write("\r" + line + "\n")
            sys.stdout.flush()
    if cancel_event.is_set():
        return False
    return not errors


def resolve_output_path(url, output, directory, suggested_name=None):
    if output:
        output_is_dir = output.endswith(("/", "\\"))
        if os.path.isdir(output) or output_is_dir:
            ensure_directory(output)
            filename = suggested_name or safe_filename_from_url(url)
            return os.path.join(output, filename)
        return output
    filename = suggested_name or safe_filename_from_url(url)
    return os.path.join(directory, filename)


def build_headers(user_agent, extra_headers):
    headers = {"User-Agent": user_agent}
    headers.update(extra_headers)
    return headers


def recursive_download(start_urls, args, headers):
    queue = deque()
    seen = set()

    for url in start_urls:
        ctx = {
            "host": parse.urlsplit(url).netloc,
            "base_path": base_path_for_no_parent(url),
        }
        queue.append((url, 0, ctx))

    while queue:
        url, depth, ctx = queue.popleft()
        normalized = normalize_url(url)
        if normalized in seen:
            continue
        seen.add(normalized)

        (
            final_url,
            total_size,
            supports_range,
            content_type,
            last_modified,
            content_disposition,
        ) = fetch_info(url, headers, args.timeout, args.max_tries)

        if not final_url:
            continue

        if depth == 0:
            ctx["host"] = parse.urlsplit(final_url).netloc
            ctx["base_path"] = base_path_for_no_parent(final_url)

        if not same_host(final_url, ctx["host"]):
            continue
        if args.no_parent and not path_within_base(final_url, ctx["base_path"]):
            continue

        final_norm = normalize_url(final_url)
        if final_norm in seen and final_norm != normalized:
            continue
        seen.add(final_norm)

        suggested_name = filename_from_content_disposition(content_disposition)
        final_path = recursive_output_path(final_url, args.directory, suggested_name)
        temp_path = temp_download_path(final_path)
        parts_path = parts_path_for(temp_path)
        ensure_directory(os.path.dirname(final_path))

        last_modified_ts = parse_http_datetime(last_modified)
        if args.overwrite:
            if os.path.exists(parts_path):
                os.remove(parts_path)
            if os.path.exists(temp_path):
                os.remove(temp_path)
            if os.path.exists(final_path):
                os.remove(final_path)

        if args.continue_download:
            if os.path.exists(parts_path) and supports_range and total_size:
                if not args.quiet:
                    print(f"Resuming {temp_path} using range metadata.")
                    success = download_multi(
                        final_url,
                        temp_path,
                        headers,
                        args.timeout,
                        total_size,
                        max(args.threads, 1),
                        args.quiet,
                        args.max_tries,
                        resume=True,
                        segment_size=args.segment_size,
                        auto_threads=args.auto_threads,
                        min_threads=args.min_threads,
                        max_threads=args.max_threads,
                        auto_window=args.auto_window,
                        auto_min_gain=args.auto_min_gain,
                    )
                if success and finalize_download(temp_path, final_path):
                    update_mtime(final_path, last_modified_ts)
                    enqueue_links(
                        queue, final_path, final_url, depth, ctx, args, content_type
                    )
                else:
                    if not args.quiet:
                        print(
                            f"Download incomplete for {temp_path}; run -c to resume."
                        )
                continue

            if os.path.exists(temp_path) and supports_range:
                existing = os.path.getsize(temp_path)
                if existing > 0:
                    if not args.quiet:
                        print(f"Resuming {temp_path} at byte {existing}.")
                    success = download_single(
                        final_url,
                        temp_path,
                        headers,
                        args.timeout,
                        existing,
                        total_size,
                        args.quiet,
                        args.max_tries,
                        cancel_event=CANCEL_EVENT,
                        thread_label="1",
                    )
                    if success and finalize_download(temp_path, final_path):
                        update_mtime(final_path, last_modified_ts)
                        enqueue_links(
                            queue, final_path, final_url, depth, ctx, args, content_type
                        )
                    elif not success and not args.quiet:
                        print(
                            f"Download incomplete for {temp_path}; run -c to resume."
                        )
                    continue

            if os.path.exists(final_path) and supports_range and total_size:
                existing = os.path.getsize(final_path)
                if existing >= total_size:
                    if not args.quiet:
                        print(f"Skipping {final_path}; already complete.")
                    enqueue_links(
                        queue, final_path, final_url, depth, ctx, args, content_type
                    )
                    continue
                if not os.path.exists(temp_path):
                    os.replace(final_path, temp_path)
                if not args.quiet:
                    print(f"Resuming {temp_path} at byte {existing}.")
                success = download_single(
                    final_url,
                    temp_path,
                    headers,
                    args.timeout,
                    existing,
                    total_size,
                    args.quiet,
                    args.max_tries,
                    cancel_event=CANCEL_EVENT,
                    thread_label="1",
                )
                if success and finalize_download(temp_path, final_path):
                    update_mtime(final_path, last_modified_ts)
                    enqueue_links(
                        queue, final_path, final_url, depth, ctx, args, content_type
                    )
                elif not success and not args.quiet:
                    print(
                        f"Download incomplete for {temp_path}; run -c to resume."
                    )
                continue

            if not supports_range and (
                os.path.exists(parts_path)
                or os.path.exists(temp_path)
                or os.path.exists(final_path)
            ):
                if os.path.exists(final_path) and total_size:
                    if os.path.getsize(final_path) >= total_size:
                        if not args.quiet:
                            print(f"Skipping {final_path}; already complete.")
                        enqueue_links(
                            queue, final_path, final_url, depth, ctx, args, content_type
                        )
                        continue
                if not args.quiet:
                    print(
                        f"Cannot resume {final_path}; server does not support ranges."
                    )
                continue

        if args.timestamping and last_modified_ts and os.path.exists(final_path):
            if os.path.getmtime(final_path) >= last_modified_ts:
                if not args.quiet:
                    print(f"Not modified: {final_path}")
                enqueue_links(
                    queue, final_path, final_url, depth, ctx, args, content_type
                )
                continue

        if not args.continue_download and not args.overwrite:
            if os.path.exists(parts_path) or os.path.exists(temp_path):
                if not args.quiet:
                    print(
                        f"Partial download found for {temp_path}; use -c to resume."
                    )
                continue
            if os.path.exists(final_path):
                if total_size and os.path.getsize(final_path) >= total_size:
                    if not args.quiet:
                        print(f"Skipping {final_path}; already complete.")
                    enqueue_links(
                        queue, final_path, final_url, depth, ctx, args, content_type
                    )
                else:
                    if not args.quiet:
                        print(
                            f"File exists: {final_path}; use -c to resume or --overwrite to restart."
                        )
                continue

        threads = max(args.threads, 1)
        if supports_range and total_size and (threads > 1 or args.auto_threads):
            if not args.quiet:
                print(
                    f"Downloading {final_url} to {temp_path} with {threads} threads."
                )
            success = download_multi(
                final_url,
                temp_path,
                headers,
                args.timeout,
                total_size,
                threads,
                args.quiet,
                args.max_tries,
                resume=False,
                segment_size=args.segment_size,
                auto_threads=args.auto_threads,
                min_threads=args.min_threads,
                max_threads=args.max_threads,
                auto_window=args.auto_window,
                auto_min_gain=args.auto_min_gain,
            )
        else:
            if not args.quiet:
                print(f"Downloading {final_url} to {temp_path}.")
            success = download_single(
                final_url,
                temp_path,
                headers,
                args.timeout,
                0,
                total_size,
                args.quiet,
                args.max_tries,
                cancel_event=CANCEL_EVENT,
                thread_label="1",
            )

        if success and finalize_download(temp_path, final_path):
            update_mtime(final_path, last_modified_ts)
            enqueue_links(queue, final_path, final_url, depth, ctx, args, content_type)
        elif not success and not args.quiet:
            print(f"Download incomplete for {temp_path}; run -c to resume.")


def main():
    parser = argparse.ArgumentParser(
        description="Simple wget-like downloader with optional multi-threading."
    )
    parser.add_argument("urls", nargs="*", help="URL(s) to download")
    parser.add_argument("-V", "--version", action="store_true", help="Show version and exit")
    parser.add_argument(
        "-O",
        "--output",
        help="Output file (single URL only); directory paths are allowed",
    )
    parser.add_argument("-P", "--directory", default=".", help="Output directory")
    parser.add_argument("-t", "--threads", type=int, default=4, help="Download threads")
    parser.add_argument(
        "--auto-threads",
        action="store_true",
        help="Adapt thread count using +/-1 probes.",
    )
    parser.add_argument(
        "--min-threads",
        type=int,
        default=1,
        help="Minimum threads for auto-threads.",
    )
    parser.add_argument(
        "--max-threads",
        type=int,
        default=64,
        help="Maximum threads for auto-threads.",
    )
    parser.add_argument(
        "--auto-window",
        type=float,
        default=60.0,
        help="Seconds per auto-threads measurement window.",
    )
    parser.add_argument(
        "--auto-min-gain",
        type=float,
        default=0.05,
        help="Minimum relative throughput gain to accept a probe.",
    )
    parser.add_argument("-c", "--continue", dest="continue_download", action="store_true")
    parser.add_argument("-r", "--recursive", action="store_true")
    parser.add_argument("-N", "--timestamping", action="store_true")
    parser.add_argument("-np", "--no-parent", dest="no_parent", action="store_true")
    parser.add_argument("--max-depth", type=int, default=5)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("-q", "--quiet", action="store_true")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT)
    parser.add_argument("--header", action="append", default=[])
    parser.add_argument("--max-tries", type=int, default=3)
    parser.add_argument(
        "--segment-size",
        default=DEFAULT_SEGMENT_SIZE,
        help="Segment size for multi-threaded ranges (bytes or K/M/G suffix).",
    )
    args = parser.parse_args()
    install_signal_handlers()

    if args.version:
        print(TOOL_VERSION)
        return 0

    if not args.urls:
        parser.print_usage(sys.stderr)
        return 2

    if args.output and len(args.urls) != 1:
        print("error: --output only supported for a single URL", file=sys.stderr)
        return 2
    if args.output and args.recursive:
        print("error: --output is not supported with --recursive", file=sys.stderr)
        return 2
    if args.status and args.recursive:
        print("error: --status is not supported with --recursive", file=sys.stderr)
        return 2
    if args.status and args.output and len(args.urls) != 1:
        print("error: --output with --status only supports a single URL", file=sys.stderr)
        return 2

    try:
        extra_headers = parse_headers(args.header)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    try:
        args.segment_size = parse_size(args.segment_size)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    if args.segment_size <= 0:
        print("error: --segment-size must be greater than 0", file=sys.stderr)
        return 2
    if args.auto_threads:
        if args.min_threads < 1:
            print("error: --min-threads must be at least 1", file=sys.stderr)
            return 2
        if args.max_threads < args.min_threads:
            print("error: --max-threads must be >= --min-threads", file=sys.stderr)
            return 2
        if args.auto_window <= 0:
            print("error: --auto-window must be greater than 0", file=sys.stderr)
            return 2
        if args.auto_min_gain < 0:
            print("error: --auto-min-gain must be >= 0", file=sys.stderr)
            return 2

    headers = build_headers(args.user_agent, extra_headers)
    ensure_directory(args.directory)
    args.max_depth = max(args.max_depth, 0)

    try:
        if args.status:
            ok = True
            for url in args.urls:
                ok = report_status(url, args) and ok
            return 0 if ok else 1
        if args.recursive:
            recursive_download(args.urls, args, headers)
            return 0

        for url in args.urls:
            (
                final_url,
                total_size,
                supports_range,
                content_type,
                last_modified,
                content_disposition,
            ) = fetch_info(url, headers, args.timeout, args.max_tries)
            suggested_name = filename_from_content_disposition(content_disposition)
            final_path = resolve_output_path(
                final_url, args.output, args.directory, suggested_name
            )
            temp_path = temp_download_path(final_path)
            parts_path = parts_path_for(temp_path)
            ensure_directory(os.path.dirname(final_path))
            last_modified_ts = parse_http_datetime(last_modified)

            if args.overwrite:
                if os.path.exists(parts_path):
                    os.remove(parts_path)
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                if os.path.exists(final_path):
                    os.remove(final_path)

            if args.timestamping and last_modified_ts and os.path.exists(final_path):
                if os.path.getmtime(final_path) >= last_modified_ts:
                    if not args.quiet:
                        print(f"Not modified: {final_path}")
                    continue

            if args.continue_download:
                if os.path.exists(parts_path) and supports_range and total_size:
                    if not args.quiet:
                        print(f"Resuming {temp_path} using range metadata.")
                    success = download_multi(
                        final_url,
                        temp_path,
                        headers,
                        args.timeout,
                        total_size,
                        max(args.threads, 1),
                        args.quiet,
                        args.max_tries,
                        resume=True,
                        segment_size=args.segment_size,
                        auto_threads=args.auto_threads,
                        min_threads=args.min_threads,
                        max_threads=args.max_threads,
                        auto_window=args.auto_window,
                        auto_min_gain=args.auto_min_gain,
                    )
                    if success and finalize_download(temp_path, final_path):
                        update_mtime(final_path, last_modified_ts)
                    else:
                        if not args.quiet:
                            print(
                                f"Download incomplete for {temp_path}; run -c to resume."
                            )
                    continue

                if os.path.exists(temp_path) and supports_range:
                    existing = os.path.getsize(temp_path)
                    if existing > 0:
                        if not args.quiet:
                            print(f"Resuming {temp_path} at byte {existing}.")
                        success = download_single(
                            final_url,
                            temp_path,
                            headers,
                            args.timeout,
                            existing,
                            total_size,
                            args.quiet,
                            args.max_tries,
                            cancel_event=CANCEL_EVENT,
                        )
                        if success and finalize_download(temp_path, final_path):
                            update_mtime(final_path, last_modified_ts)
                        elif not success and not args.quiet:
                            print(
                                f"Download incomplete for {temp_path}; run -c to resume."
                            )
                        continue

                if os.path.exists(final_path) and supports_range and total_size:
                    existing = os.path.getsize(final_path)
                    if existing >= total_size:
                        if not args.quiet:
                            print(f"Skipping {final_path}; already complete.")
                        continue
                    if not os.path.exists(temp_path):
                        os.replace(final_path, temp_path)
                    if not args.quiet:
                        print(f"Resuming {temp_path} at byte {existing}.")
                    success = download_single(
                        final_url,
                        temp_path,
                        headers,
                        args.timeout,
                        existing,
                        total_size,
                        args.quiet,
                        args.max_tries,
                        cancel_event=CANCEL_EVENT,
                    )
                    if success and finalize_download(temp_path, final_path):
                        update_mtime(final_path, last_modified_ts)
                    elif not success and not args.quiet:
                        print(
                            f"Download incomplete for {temp_path}; run -c to resume."
                        )
                    continue

                if not supports_range and (
                    os.path.exists(parts_path)
                    or os.path.exists(temp_path)
                    or os.path.exists(final_path)
                ):
                    if os.path.exists(final_path) and total_size:
                        if os.path.getsize(final_path) >= total_size:
                            if not args.quiet:
                                print(f"Skipping {final_path}; already complete.")
                            continue
                    if not args.quiet:
                        print(
                            f"Cannot resume {final_path}; server does not support ranges."
                        )
                    continue

            if not args.continue_download and not args.overwrite:
                if os.path.exists(parts_path) or os.path.exists(temp_path):
                    if not args.quiet:
                        print(
                            f"Partial download found for {temp_path}; use -c to resume."
                        )
                    continue
                if os.path.exists(final_path):
                    if total_size and os.path.getsize(final_path) >= total_size:
                        if not args.quiet:
                            print(f"Skipping {final_path}; already complete.")
                    else:
                        if not args.quiet:
                            print(
                                f"File exists: {final_path}; use -c to resume or --overwrite to restart."
                            )
                    continue

            threads = max(args.threads, 1)
            if supports_range and total_size and (threads > 1 or args.auto_threads):
                if not args.quiet:
                    print(
                        f"Downloading {final_url} to {temp_path} with {threads} threads."
                    )
                success = download_multi(
                    final_url,
                    temp_path,
                    headers,
                    args.timeout,
                    total_size,
                    threads,
                    args.quiet,
                    args.max_tries,
                    resume=False,
                    segment_size=args.segment_size,
                    auto_threads=args.auto_threads,
                    min_threads=args.min_threads,
                    max_threads=args.max_threads,
                    auto_window=args.auto_window,
                    auto_min_gain=args.auto_min_gain,
                )
            else:
                if not args.quiet:
                    print(f"Downloading {final_url} to {temp_path}.")
                success = download_single(
                    final_url,
                    temp_path,
                    headers,
                    args.timeout,
                    0,
                    total_size,
                    args.quiet,
                    args.max_tries,
                    cancel_event=CANCEL_EVENT,
                    thread_label="1",
                )

            if success and finalize_download(temp_path, final_path):
                update_mtime(final_path, last_modified_ts)
            elif not success and not args.quiet:
                print(f"Download incomplete for {temp_path}; run -c to resume.")
    except KeyboardInterrupt:
        if not args.quiet:
            print("Interrupted; partial downloads kept.")
        return 130

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
