1.	Verify you are not on main. You must be on your agent branch.
2.	git fetch origin
3.	git rebase origin/main
	•	If conflicts: resolve, ensure build/tests pass, then git rebase --continue. If you cannot resolve confidently, stop and ask.
4.	Examine uncommitted changes. Remove temp debugging, throwaway logs, and accidental files. Keep the diff minimal and intentional.
5.	Run ./scripts/lint to auto-format code. This prevents style thrash across commits.
6.	If the code or approach looks janky/unsafe/unclear, stop and ask for clarification.
7.	Stage changes and create a commit with a precise message.
8.	Push to main:
	•	git push origin HEAD:main
	•	If this fails (another agent pushed), repeat from step 2.

Rules:
	•	Never work directly on main; use your agent branch for isolation.
	•	Never merge main into the agent branch; rebase only.
	•	Never force-push main.
