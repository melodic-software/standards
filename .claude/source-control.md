# source-control configuration

Team-tracked layer consumed by the `source-control@melodic-software` plugin. Key names, valid
values, and resolution order are defined upstream in
<https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/reference/config-resolution.md>
— the `babysit_loop_*` keys under "Loop-lane keys (`babysit_loop_*`)", and
`pr_body_required_sections` under "The config surface". The merge-rung ladder and the ratification
rule that makes this reviewed file the recorded baseline are defined in
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/loop-lane/README.md>.

## babysit_loop_stop_mode

standing

## babysit_loop_tier

worker

## babysit_loop_merge

c3-autonomous

## babysit_loop_grace_window_minutes

30

## pr_body_required_sections

- Summary
- Test plan
- Related
