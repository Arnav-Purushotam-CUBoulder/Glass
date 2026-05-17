# Release Notes

## Build

```bash
swift build --package-path Glass -c release
./Glass/BuildSupport/build-app.sh
```

Expected output:

```text
Glass/build/Glass.app
```

## Local Install

```bash
rm -rf /Applications/Glass.app
cp -R Glass/build/Glass.app /Applications/Glass.app
open -a /Applications/Glass.app
```

## Release Checklist

1. Verify `swift build --package-path Glass -c release`
2. Verify `./Glass/BuildSupport/build-app.sh`
3. Launch the packaged app and test overlay visibility, close button behavior, and permissions
4. Update `CHANGELOG.md`
5. Tag the release and upload the packaged artifacts if distributing binaries
