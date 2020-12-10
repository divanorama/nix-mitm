{pkgs ? import (builtins.fetchTarball {
  url = "https://github.com/nixos/nixpkgs/archive/e0732437e0790ceb447e4f529be29ae62507262b.tar.gz";
  sha256 = "0zrr9dzqvsyipwp4ckpj3mhlqy4dvm2wn3z19vn0ny15bvq8s4g0";
}) {}}: let

maplocal2 = builtins.fetchurl {
  name = "maplocal2.py";
  url = "https://raw.githubusercontent.com/divanorama/mitmproxy_addons/e09fe0a4b5bfdd71ded36a364d554afbd92ffa46/maplocal2.py";
  sha256 = "4c1fb6be144237a640959080152f820c9e8a4ff7ad71dd6c7b6e751229e25265";
};

# Shell script part to start mitmproxy and export common proxy configuration env vars
start = {args ? "", cachedDeps ? [], offline ? true}: ''
function getFreePort() {
  # TODO: pick random free port?
  echo 9999
}
function waitPort() {
  # TODO: probe for port, or use mitmproxy addon hooks?
  sleep 5
}
port=$(getFreePort)
host=127.0.0.1


# Dry run to create certificates, could also do it via openssl
cfg=$(mktemp -d)
HOME="$cfg" "${pkgs.mitmproxy}"/bin/mitmdump -n -r "$(mktemp)" -q

# Prepare java trust store for java clients
ca_cer="$cfg"/.mitmproxy/mitmproxy-ca-cert.cer
java_ca=$(mktemp -d)/jks
java_ca_pass="qwerty"
tmp_ca=$(mktemp -d)/p12
"${pkgs.openssl}"/bin/openssl pkcs12 -export -in "$ca_cer" -inkey "$cfg"/.mitmproxy/mitmproxy-ca.pem -passout pass:qwerty -out "$tmp_ca"
"${pkgs.jre}"/bin/keytool -importkeystore -srckeystore "$tmp_ca" -srcstoretype PKCS12 -srcstorepass qwerty -destkeystore "$java_ca" -deststoretype pkcs12 -deststorepass "$java_ca_pass"

# Start the proxy
HOME="$cfg" "${pkgs.mitmproxy}"/bin/mitmdump -p "$port" --listen-host "$host" "--server-replay-nopop" "-s" "${maplocal2}" --set map_local2_404=${pkgs.lib.boolToString offline} --set map_local2_file="${deps2mapLocal2File cachedDeps}" ${args} &
pid=$!
trap "kill $pid" EXIT
waitPort "$port"

# Export common ways to define proxy configuration
export http_proxy="http://$host:$port"
export https_proxy="http://$host:$port"
export SSL_CERT_FILE="$ca_cer"
export NIX_SSL_CERT_FILE="$ca_cer"
export JAVA_OPTS="-Dhttp.proxyHost=$host -Dhttp.proxyPort=$port -Dhttps.proxyHost=$host -Dhttps.proxyPort=$port -Djavax.net.ssl.trustStore=$java_ca -Djavax.net.ssl.trustStorePassword=$java_ca_pass $JAVA_OPTS"
export SBT_OPTS="-Dhttp.proxyHost=$host -Dhttp.proxyPort=$port -Dhttps.proxyHost=$host -Dhttps.proxyPort=$port -Djavax.net.ssl.trustStore=$java_ca -Djavax.net.ssl.trustStorePassword=$java_ca_pass $SBT_OPTS"
export COURSIER_OPTS="$JAVA_OPTS"
export MAVEN_OPTS="$JAVA_OPTS"
# can either put "startup $BAZEL_STARTUP_OPTS" to bazelrc or invoke "bazel $BAZEL_STARTUP_OPTS"
export BAZEL_STARTUP_OPTS="$(echo "$JAVA_OPTS" | ${pkgs.gnused}/bin/sed -e 's/-D/--host_jvm_args=-D/g')"
'';

# Urls with very long name or some special chars are rejected by Nix, let's replace & truncate in an automated way
nameFromURL = url:
  let
    components = pkgs.lib.splitString "/" url;
    filename = pkgs.lib.last components;
  in builtins.replaceStrings ["~" "&" "%"] ["_" "_" "_"] (builtins.substring 0 (pkgs.lib.min 207 (builtins.stringLength filename)) filename);

# Run mitmdump on recorded flow, with args="-s ${dumpscript}" will print urls and checksums to stdout
processdump = {args, dump}: ''HOME="$(mktemp -d)" "${pkgs.mitmproxy}"/bin/mitmdump -r "$dump" -n ${args}'';

# Convert [ {url=; sha256=;} ... ] to maplocal2 addon configuration file with |url|file lines
deps2mapLocal2File = networkDepsList: let
  # mapping format is @url@path where @ can be arbitrary character
  f = {url, sha256}: ''|${url}|${pkgs.fetchurl { url = url; sha256 = sha256; name = nameFromURL url; }}'';
  in pkgs.writeTextFile  {
    name = "map_local2_mapping_file";
    text = builtins.concatStringsSep "\n" (map f networkDepsList);
  };

# Print fetched urls with content sha256 and redirects
dumpscript = pkgs.writeTextFile {
  name = "logscript.py";
  text = ''
import hashlib
import sys

def response(flow):
    if flow.request.method == "GET" and flow.response.status_code == 200:
        print ("GET\t%s\t%s" % (flow.request.url, hashlib.sha256(flow.response.content).hexdigest()))
    elif flow.request.method == "GET" and flow.response.status_code == 302:
        print ("REDIR\t%s\t%s" % (flow.request.url, flow.response.headers.get("Location", "")))
  '';
};

# Convert from dumpscript output to Nix attrset list suitable for being used as cachedDeps
dumpconv = ''${pkgs.python}/bin/python ${pkgs.writeTextFile {
  name = "conv.py";
  text = ''
import sys

res, redir, resolving = {}, {}, {}

for l in sys.stdin.readlines():
    a, b, c = l.strip().split('\t')
    (res if a == "GET" else redir if a == "REDIR" else None)[b] = c

def go (k):
    if k in res or k in resolving:
        return res[k] if k in res else None
    resolving[k] = True
    res.update({k: v for v in [go(redir.get(k))] if v})

map (go, redir)
print ("[")
for (k, v) in sorted(res.items()):
    print ('    { "url" = "%s"; "sha256" = "%s"; }' % (k, v))
print ("]")
  '';
}}'';
in {
  inherit start dumpscript processdump dumpconv;
  # export mitmproxy package for package/script debugging convenience
  mitmproxy = pkgs.mitmproxy;
}
