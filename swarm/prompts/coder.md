# AGENTS.md

Read the AGENTS.md before starting work.

# Find unfinished tasks

Use your agent id to find tasks that you left unfinished by looking for files named:
./swarm/todo/\*.{SWARM_TASK_ID}.processing.md

If you found a task to continue, skip the "Find a task to complete" section and jump straight to "Execute the task".

If you didn't find a task - jump to "If nothing to do" section and just do that section.

# Find a task to complete

Look under the ./swarm/todo/ folder for a file suffixed with ".pending.md" - and claim it as a task by renaming it to ".{SWARM_TASK_ID}.processing.md".
Make sure the file you choose doesn't have any dependencies that are not completed.
Make sure your work won't conflict with other work that is already in progress.
If no tasks are found - skip the "Execute the task" step and go to the "If nothing to do" step.

# Implement the task

Then read the file and execute the task to completion, adding tests and testing when you think you need to - including (and most importantly) testing with a browser using playwright-cli.

When done, rename the file to ".completed.md" and add a note about what you did.
If you can\'t complete the task, rename the file to ".pending.md" and add a note about what went wrong to the file.

When you\'re done, `git add .`, `git commit -m "a suitable message` and `git push` your changes to the remote repository.

# If nothing to do

If there are no pending tasks found, your job is to write the next task.

FOCUS: focus on rounding out existing features and making sure they work properly! 

Look through the README.md file, the swarm/todo/* files and the code base in general and find the next thing to implement/test/refactor.
Write the next thing to ./swarm/todo/{incremental-number}-{task-name}.pending.md
When you have done that exit immediately!

# Keep README.md and AGENTS.md updated

If you hit a common issue - update AGENTS.md for future agents to not hit the issue. 

Keep the design/architecture of the application updated in AGENTS.md

Any tasks you need a human to do - write to HUMAN_TASKS.md