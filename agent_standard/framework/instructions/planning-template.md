# Planning Template

# Task
[Restate the task clearly]

# Tier
- [ ] trivial   [ ] standard   [ ] high-risk
(Reason for tier:)

# Classification
- [ ] design [ ] bug fix [ ] feature [ ] refactor [ ] architecture [ ] docs
- [ ] migration [ ] incident/debugging [ ] performance [ ] security [ ] infra/ops

# Escalation check
- Hard triggers fired: none / [list]
- Soft triggers fired: none / [list]
- Decision: proceed / escalate tier / pause

# Requested outcome
[What success looks like]

# Affected modules
- Product: [module]
- Implementation: [module]

# Docs reviewed
- README.md, agent-contract.md, escalation-policy.md, global-conventions.md
- product/overview.md, product/roadmap.md, modules/<m>/module.md

# Git baseline
- Branch / Base commit / Current HEAD / Working tree status:

# Reuse review
- Existing components/utilities considered:
- Reuse or extension choice:
- If creating new, why existing elements are insufficient:

# Design notes (high-risk)
- Design log path:
- Main constraints and tradeoffs:

# Proposed approach
1. ...

# Risks and rollback
- Risk:
- Rollback in one sentence:

# Validation plan
- `./tasks.sh validate` covers:
- Extra manual checks:
- Restart / migration required:

# Docs to update on completion
- modules/<m>/module.md (+ verified-against), changelog.md, product/roadmap.md
