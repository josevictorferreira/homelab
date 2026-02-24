---
active: true
iteration: 1
max_iterations: 1000
completion_promise: "DONE"
started_at: "2026-02-24T16:23:55.715Z"
session_id: "ses_36f891ff3ffe1GfVtZ2HHYytTy"
strategy: "continue"
---
Fix all lint errors found in the code(not just formatting issues), launch multiple agents to work in parallel(max 6 up) to be faster, dont stop until all of the lint errors are fixed. Your job as an agent is to orchestrate all of that and validate if the fixes worked, if fail still, launch an agent again and continue until all of the lint errors are fixed in the whole project.
