# wget

A small Python downloader with wget-like behavior and optional multi-threaded downloads.

## Usage

From source:

```bash
python wget.py https://example.com/file.zip
python wget.py -t 8 https://example.com/file.zip
python wget.py -c https://example.com/file.zip
python wget.py -P downloads https://example.com/file.zip
python wget.py -O output.zip https://example.com/file.zip
python wget.py -O downloads/ https://example.com/file.zip
python wget.py -r -N -c -np -P downloads https://example.com/path/
python wget.py --segment-size 4MB -t 8 https://example.com/bigfile.bin
python wget.py -c -P downloads -t 4 --timeout 120 https://example.com/bigfile.bin
python wget.py --overwrite -P downloads -t 4 https://example.com/bigfile.bin
python wget.py --status -P downloads https://example.com/bigfile.bin
python wget.py --version
```

After build/install:

```bash
wget https://example.com/file.zip
wget -t 8 https://example.com/file.zip
wget -c https://example.com/file.zip
wget -P downloads https://example.com/file.zip
wget -O output.zip https://example.com/file.zip
wget -O downloads/ https://example.com/file.zip
wget -r -N -c -np -P downloads https://example.com/path/
wget --version
```

## Notes

- Multi-threaded mode requires server support for HTTP range requests and a known content length.
- Resume mode falls back to a single-thread range request when possible.
- Recursive mode defaults to depth 5; override with `--max-depth`.
- Large files may need a higher `--timeout` value.
- Incomplete downloads are saved as `filename.ext.par` with a `.par.parts` resume map; successful downloads are renamed to the final filename.
- Multi-threaded downloads keep going after a range failure; use `-c` to finish missing ranges.
- Default `--segment-size` is 1MB; smaller values improve resume granularity at the cost of more metadata.
- To change `--segment-size` for an existing partial, remove the `.par.parts` file or use `--overwrite`.
- Existing files are kept unless you pass `-c` or `--overwrite`.
- Ctrl+C stops the run and keeps partial files; rerun with `-c` to continue.
- `--status` scans for a matching `.par.parts` file and reports progress from it.

## Versioning

- Tool version stored in `scripts\wget\VERSION`
- Exposed via `wget --version` (embedded at build time)
- Release notes in `scripts\wget\RELEASE_NOTES.md`
