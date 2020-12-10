## Prototype for generic network dependencies in Nix packages

### Goals
1. No use of Fixed-Output Derivations as they break out of sandbox
2. Can work without conversion of package build system via something2nix or similar

### Outline
1. Spin up [mitmproxy](https://github.com/mitmproxy/mitmproxy/) on sandbox localhost network
2. Map known network dependencies to hermetic files via addon similar to [map\_local](https://docs.mitmproxy.org/stable/overview-features/#map-local)
3. To update/create dependencies use mitmproxy outside of build sandbox, and analyze its dump
4. This does not prevent simultaneous use of more efficient ways to supply provided/cached dependencies specific to a given build tool
5. It's possible to have some more complex proxy script logic like ignoring some of request parameters for example

### Current limitations
1. Each url is converted to a separate fetchurl derivation
2. Only supported request/responses are HTTP GET 200, HTTP HEAD 200 (without Content-Length), redirects and 404 for missing URLs
3. Spinning up mitmproxy and running other commands is provided as a **String** to be injected into build script
4. Git, ssh+git, rsync and many other network protocols aren't currently supported

### Trying it out
```sh
cd examples
nix-build hello.nix -A hello

# let's try to update deps
nix-build hello.nix -A updater
./result | tee hellodeps.nix
```

### Potenital improvements
1. Built-in support of env vars for more build tools
2. Support to supply dependencies directly to build tool download/dependency cache
3. Option to package multiple dependencies into single derivation
4. Generate .sha1,.md5 urls on the fly rather that having derivations for them
5. Option to extract network log/dump, both for updater and builder
6. Running updater in environment almost identical to build sandbox (real build sandbox + single firewall hole + proxy outside of build sandbox?)
7. Maybe support transparent proxy mode + firewall forwarding + modified "system" CA certificates in build sandbox for even simplier integration with builds
8. Code improvements etc
