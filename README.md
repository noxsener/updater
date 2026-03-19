### Scan current directory, write files.json
./codenfast_updater --generate

### With ignore patterns (repeatable flag)
./codenfast_updater --generate --ignore "*.log" --ignore "build/"

### Comma-separated patterns in one flag also work
./codenfast_updater -g --ignore "*.log,build/,secrets/,*.tmp"

### Control where the JSON is written
./codenfast_updater -g --output "dist/files.json"

### Set the base URL embedded in each file's `url` field
./codenfast_updater -g --base-url "https://cdn.myserver.com/bot"

### Add runCommands for this OS
./codenfast_updater -g --run "wirecutterbot.exe" --run "cleanup.bat"

### Override OS label (instead of auto-detecting)
./codenfast_updater -g --os windows

## Example
```
./codenfast_updater --generate --base-url "http://app.codenfast.com/eimza2"  --ignore "data/" --ignore "codenfast_updater" --run "./java-17-openjdk-amd64/bin/java -jar"
```

### Ignore pattern support (_IgnoreMatcher)

| Pattern | What it ignores|
| :--- | :----- |
|*.log | Any file whose name ends in .log|
|build/ or build | Any path segment named build|
|src/gen/*.dart | Glob match on relative path|
|**/temp | Any segment named temp at any depth|
| secrets/key.pem | Exact relative path match|
| Thumbs.db| Exact filename anywhere|