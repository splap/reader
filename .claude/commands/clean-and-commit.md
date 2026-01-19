1.	Verify you are not on main. You must be on the agent’s long-lived private branch.
2.	git fetch origin
3.	git rebase origin/main
    •	If conflicts: resolve, ensure build/tests pass, then git rebase --continue. If you cannot resolve confidently, stop and ask.
4.	Examine uncommitted changes. Remove temp debugging, throwaway logs, and accidental files. Keep the diff minimal and intentional.
5.	If the code or approach looks janky/unsafe/unclear, stop and ask for clarification.
6.	If OK: stage changes and create a commit with a precise message.
7.	Push the agent branch update to origin (rebasing rewrites history, so use the safe force push):
    •	git push --force-with-lease origin HEAD
8.	Switch to main and merge the agent branch into it:
    •	git checkout main
    •	git pull origin main
    •	git merge <agent-branch>
    •	git push origin main
9.	Switch back to the agent branch:
    •	git checkout <agent-branch>

Rules:
	•	Never merge main into the agent branch; rebase only.
	•	Never force-push main.
	•	Always merge agent branch into main after committing, so other agents can pull the latest.