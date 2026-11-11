# Test counts for the PR description

Read from `SKILL.md`, "PR description". The rules are there; this file holds how the counts of Tier 1 are taken.

   - One count per module and test task: each KMP module per target (`domain`, `data`:
     `testAndroidHostTest` and `iosSimulatorArm64Test`; `shared` and `shared-uitest`:
     `iosSimulatorArm64Test`),
     each Android module's `testDebugUnitTest`.
   - A count is the `tests` attribute summed over the XML files in
     `<module>/build/test-results/<task>/` after the gate's `allTests test` run.
   - All counts at once:
     `for d in */build/test-results/*/ androidApp/*/build/test-results/*/; do echo "$d $(cat "$d"*.xml | grep -o '<testsuite [^>]* tests="[0-9]*"' | sed 's/.* tests="//; s/"//' | awk '{s+=$1} END {print s+0}')"; done`
