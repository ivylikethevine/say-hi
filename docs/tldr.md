# hi

> Copy your shell config to a target, start a session, and clean up on exit.
> Resolves the target in order: SSH host, container, Nomad job, Kubernetes pod.
> More information: <https://github.com/ivylikethevine/say-hi>.

- Start an interactive session on an SSH host, with your prompt and aliases:

`hi {{host}}`

- Run a single command on a target and exit, the way ssh does:

`hi {{host}} '{{command}}'`

- Start a session inside a running container, allocation, or pod:

`hi {{name_or_id}}`

- Connect through a jump host (every ssh option passes through unchanged):

`hi -J {{bastion}} {{host}}`

- Diagnose a slow or failing target (backends, config, and reachability):

`hi --doctor {{host}}`

- Print the installed version:

`hi --version`

- Re-run the feature toggle prompts (header, prompt, git status, aliases):

`hi --configure`
