# hi

> Copy your shell config to a target, start a session, and clean up on exit.
> Resolves the target in order: SSH host, container, Nomad allocation, Kubernetes pod.
> More information: <https://github.com/ivylikethevine/say-hi>.

- Start an interactive session on an SSH host, with your prompt and aliases:

`hi {{host}}`

- Pick a target from the list of everything reachable:

`hi`

- Run a single command inside the session (with hi's aliases and environment) and exit:

`hi {{host}} '{{command}}'`

- Start a session inside a running container, allocation, or pod:

`hi {{name_or_id}}`

- Connect through a jump host (every ssh option passes through unchanged):

`hi -J {{bastion}} {{host}}`

- Force a backend instead of probing, when a container shadows an SSH host of the same name:

`hi --use {{ssh|docker|podman|nomad|kube}} {{container}}`

- Open a bare shell with nothing copied, on a target with no writable `/tmp`:

`hi --plain {{target}}`

- Diagnose a slow or failing target (backends, config, and reachability):

`hi --doctor {{host}}`
