# hi

> Copy your shell config to a target, start a session, and clean up on exit.
> Resolves the target in order: SSH host, container, Nomad job, Kubernetes pod.
> More information: <https://github.com/ivylikethevine/say-hi>.

- Start an interactive session on an SSH host, with your prompt and aliases:

`hi {{host}}`

- Pick a target from the list of everything reachable:

`hi`

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

- Force an arm by name instead of probing (ssh, docker, podman, nomad, kube), for a container that shadows an ssh host:

`hi --use {{docker}} {{name}}`

- Hand over a bare shell with nothing copied - no aliases, no header - on whatever the target resolves to:

`hi --plain {{target}}`

- Preview what every ssh host and your user resolve to, in their colors:

`hi --preview-colors`
