# clever-computer

A sandbox for AI coding agents allowing them to run "safely" without ever
stopping to ask for permission, along with some workflows that take advantage of
this to make it really easy to manage a bunch of agents working on different
tasks in parallel.

The sandboxing idea is:

* Allow full unrestricted access to the public internet so that the AI never has
  to ask permission to look something up or download dependencies.

* Mount a host directory RW on the VM where all the coding happens.

* Don't put any credentials on the VM so that the AI can't do any destructive
  actions on private resources, and can't even leak credentials.

* Give the VM capabilities to perform specific safer actions on private
  resources, e.g. create/read/update PRs on a GitHub repo. But not e.g. push to
  `main`.

## Project Organization

Code that runs on the host is in `host/` and code that runs in the sandbox is in
`sandbox/`, to make it clear which code needs to be trusted.

## VM Capabilities

### GitHub

A PitM proxy running on the host adds authorization to GitHub API requests coming from the VM.

### Claude Code

To give the VM's Claude Code access to my subscription, I just log in from the
VM. This is a violation of "don't put any credentials on the VM," but it's fine
for now because leaking this credential should only allow attackers to steal
some of my usage quota, not to do anything else.

## Sandbox Hole

I can think of one hole in this sandbox. The AI could read private data using
its capabilities and then post them to the public internet.

I don't care about this hole right now because I'm only using this sandbox to do
opensource development on public code and none of the capabilities give the VM
access to private data.

In the future, it might be possible to partially close this hole by having a
public internet allowlist instead of full unrestricted access. This doesn't
completely close the hole, because the AI could still exfiltrate data through
obfuscated GET requests to a malicious package server that logs the requests and
reconstructs the data.

I guess we could close the hole even better by having private mirrors of
everything that the AI needs.
