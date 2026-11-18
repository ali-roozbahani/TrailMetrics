# When the permission classifier denies a command

Moved word for word from `SKILL.md`. The rules are unchanged; they are still cited as `tm-agent-loop`, "When the permission classifier denies a command".

## When the permission classifier denies a command

A denied command is the owner's "no" for that command, not an obstacle to route around.

- Do not run it again, and do not try another route to the same effect (a different tool, a
  wrapper, a rewritten or split command, a script that does the same, an edit of the settings or
  of a hook).
- Stop that step. Say which command was denied (quote the denial message) and what it would have
  done.
- Then go on with the rest of the queue (`queue.sh next`), or, when the denied step belongs to a
  PR and the PR cannot go on without it, hand that PR to the owner: set its entry as for a
  condition of section 8 that is "no", post the Merge check comment with the denial as the reason,
  and take the next entry. Section 8's merge conditions are unchanged; a PR whose step was denied
  is never merged by the agent on the strength of another route.
- The denial goes in the final report under Not done, with the quoted message (see "Report").
