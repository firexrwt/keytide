# Sourced by build-app.sh and make-dmg.sh. Sets $sign to the release signing identity, or "-" when this machine
# has none (the private key lives only in CI and an offline backup). find-identity needs the key, not just the
# certificate; the self-signed root is untrusted, so no -v.
identity="${KEYTIDE_SIGN_IDENTITY:-Keytide Code Signing}"
identities=$(security find-identity -p codesigning 2>/dev/null || true)
if [[ "$identities" == *"\"$identity\""* ]]; then
    sign="$identity"
elif [ "${KEYTIDE_REQUIRE_IDENTITY:-0}" = 1 ]; then
    echo "Signing identity '$identity' not found" >&2; exit 1
else
    sign=-
fi
