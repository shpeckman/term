# term

`term` is a Crystal shard for building terminal applications on the kitty family of terminal protocols. One class, `Term`, puts the terminal into raw mode, turns everything the terminal sends into typed events on a channel, and gives you methods for everything you send back.

It covers:

- the Kitty keyboard protocol, with taps, holds, chords, key sequences and shortcuts derived from it
- pixel-precise mouse reporting, with clicks, drags, hover, scroll and swipe gestures
- resize, focus, visibility and color-scheme notifications
- pointer shapes (OSC 22)
- color stack and color set/query (OSC 21)
- MIME-typed clipboard and paste events (OSC 5522)
- the kitty graphics protocol, including animation and Unicode placeholders
- desktop notifications (OSC 99)
- drag and drop, including remote files and directories (OSC 72)

On terminals that lack these protocols, `term` falls back to legacy keyboard input, cell-based mouse reports and bracketed paste.

## Requirements

- Crystal `>= 1.21.0`
- Linux or macOS. macOS support is written but untested. Windows is not supported.
- No dependencies beyond the standard library (OpenSSL and zlib are linked).

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  term:
    github: shpeckman/term
```

Then run `shards install` and:

```crystal
require "term"
```

## Quick start

```crystal
require "term"

Term.open do |term|
  term.print "\e[2J\e[HPress q to quit"
  while event = term.events.receive?
    case event
    when Term::TextInput then break if event.text == "q"
    when Term::Mouse     then term.print "\e[2;1H#{event.col},#{event.row}  "
    when Term::Resize    then term.print "\e[3;1H#{event.cols}x#{event.rows}  "
    end
  end
end
```

- `Term.open` probes what the terminal supports, enables it, yields, and restores the terminal afterwards. The terminal is also restored on an exception, on `exit`, and on `SIGINT`, `SIGTERM`, `SIGHUP` and `SIGQUIT`.
- `term.events` is a `Channel(Term::Event)`. Read it from one fiber; `receive?` returns `nil` once the terminal is closed.
- `term.print` and `term <<` are safe to call from any fiber. `term` does no drawing for you: cursor movement and text styling are your own escape sequences.
- Queries such as clipboard reads block the calling fiber and return the answer, or `nil` on timeout.

## How it behaves

### Support detection

At open, `term` asks the terminal about each feature and enables only what is supported. The result is in `term.features`:

```crystal
term.features.keyboard?     # Kitty keyboard protocol
term.features.pixels?       # pixel mouse coordinates
term.features.paste?        # MIME-typed paste events
term.features.resize?       # in-band resize reports
```

The full set is `Keyboard`, `Resize`, `Motion`, `Pixels`, `Focus`, `Visibility`, `ColorScheme` and `Paste`.

| Missing feature                 | Fallback                                                                                                                                                                                                                  |
|---------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Kitty keyboard                  | Typed bytes become key events, each as a press followed at once by a release. Holds and chords are unavailable; Tab and Ctrl-I, and Enter and Ctrl-M, cannot be told apart; a lone Escape is reported after about 100 ms. |
| Pixel mouse                     | SGR cell reports. `col` and `row` are exact; `x` and `y` are the cell's top-left corner.                                                                                                                                  |
| MIME paste                      | Bracketed paste. The `Paste` event carries the text in its `text` field.                                                                                                                                                  |
| In-band resize                  | The window size is read from the terminal, and `SIGWINCH` produces a `Resize` event.                                                                                                                                      |
| Focus, visibility, color scheme | None. These events are simply absent.                                                                                                                                                                                     |

A terminal that answers nothing delays `Term.open` by `query_timeout` (1 second by default). Set `config.detect = false` to skip probing and enable everything unchecked.

### Signals and job control

While a `Term` is open the shard installs handlers for `SIGINT`, `SIGTERM`, `SIGHUP`, `SIGQUIT`, `SIGTSTP`, `SIGCONT` and `SIGWINCH`. They replace any handlers you installed and are not removed on close. Set `config.signals = false` to keep your own, and call `Term.restore`, `Term.suspend`, `Term.resume` and `Term.refresh` from them as needed.

Ctrl-Z suspends the process as a shell user expects: the terminal modes are left, the process group is stopped, and the modes are re-entered on continue. The key event is still delivered. Set `config.job_control = false` to handle Ctrl-Z yourself.

### Events and back-pressure

Events are queued internally, so a slow consumer never blocks queries. If more than `config.event_backlog` events (65,536 by default) pile up, the oldest are dropped.

### Blocking queries

Methods that ask the terminal a question return its answer, or `nil` if none arrives in time. Most accept a trailing `limit : Time::Span`; the default is `config.query_timeout`, or `config.clipboard_timeout` and `config.transfer_timeout` for clipboard and drag-and-drop transfers, since the terminal may prompt the user.

## Configuration

```crystal
config = Term::Config.new
config.app_name = "editor"
config.shortcut("save", 's', Term::Mods::Ctrl)
config.chord("jk", 'j', 'k')
config.sequence("leader-f", ' ', 'f')

Term.open(config) do |term|
  # ...
end
```

| Option                       | Default   | Meaning                                                                                                    |
|------------------------------|-----------|------------------------------------------------------------------------------------------------------------|
| `alternate_screen`           | `true`    | Use the alternate screen                                                                                   |
| `detect`                     | `true`    | Probe support at open                                                                                      |
| `signals`                    | `true`    | Install the signal handlers                                                                                |
| `job_control`                | `true`    | Ctrl-Z suspends the process                                                                                |
| `app_name`                   | `nil`     | Name shown in clipboard permission prompts; also enables a per-run password so the user is asked only once |
| `clipboard_id`               | `"term"`  | Request id for clipboard reads, for multiplexer routing                                                    |
| `dnd_id`                     | `0`       | Multiplexer id added to drag-and-drop codes                                                                |
| `query_timeout`              | 1 s       | Default wait for queries and for startup probing                                                           |
| `clipboard_timeout`          | 30 s      | Wait for clipboard transfers                                                                               |
| `transfer_timeout`           | 30 s      | Wait for drag-and-drop transfers                                                                           |
| `busy_retries`, `busy_delay` | 3, 100 ms | Clipboard retry when the terminal reports `EBUSY`                                                          |
| `event_buffer`               | 1024      | Capacity of the `events` channel                                                                           |
| `event_backlog`              | 65536     | Internal queue cap before the oldest events are dropped                                                    |
| `hold_repeats`               | 3         | Repeats before `HoldReached`                                                                               |
| `hold_after`                 | 500 ms    | Time before a press becomes a hold when no repeat arrives                                                  |
| `multi_tap_window`           | 300 ms    | Window for counting consecutive taps                                                                       |
| `sequence_timeout`           | 1 s       | Reset time for key sequences                                                                               |
| `click_radius`               | 4 px      | Distance a click may move                                                                                  |
| `click_window`               | 300 ms    | Longest press that counts as a click                                                                       |
| `multi_click_window`         | 400 ms    | Window for double and triple clicks                                                                        |
| `long_press_after`           | 500 ms    | Time before a mouse press becomes a long press                                                             |
| `hover_dwell_after`          | 500 ms    | Time before a still pointer reports a dwell                                                                |
| `hover_radius`               | 4 px      | Movement tolerated during a dwell                                                                          |
| `scroll_window`              | 50 ms     | Window for coalescing wheel reports                                                                        |
| `swipe_velocity`             | 500 px/s  | Speed at which a drag also reports a swipe                                                                 |

Bindings:

- `chord(name, *keys)` fires when all keys are held together.
- `sequence(name, *keys)` fires when the keys are pressed one after another.
- `shortcut(name, key, mods = Mods::None, physical: false)` fires on a key with modifiers. With `physical: true` it matches the key's position on a standard layout, so it works regardless of keyboard layout.

A key is a `Char`, a `Term::Named` or a raw key code. Bindings arrive as `Term::Binding` events carrying the name.

## Events

Everything on `term.events` is one of the following.

### Keyboard

| Event          | Fields                                              | When                                                 |
|----------------|-----------------------------------------------------|------------------------------------------------------|
| `Key`          | `code`, `action`, `mods`, `shifted`, `base`, `text` | Every press, repeat and release                      |
| `TextInput`    | `text`                                              | A key produced text                                  |
| `KeyCommand`   | `key`                                               | A key did not produce text                           |
| `KeyGesture`   | `kind`, `key`, `count`                              | See kinds below                                      |
| `Binding`      | `kind`, `name`                                      | A registered `Chord`, `Sequence` or `Shortcut` fired |
| `Lock`         | `lock`, `active`                                    | Caps lock or num lock toggled                        |
| `TypingMetric` | `code`, `dwell`, `latency`, `overlap`               | On each key release                                  |

`Key` helpers: `named` (a `Term::Named` or `nil`), `char`, `press?`, `repeat?`, `release?`, `shift?`, `alt?`, `ctrl?`, `modifier?`, `command?`.

`KeyGesture` kinds: `Activate`, `AutoRepeat`, `Tap`, `MultiTap`, `HoldStart`, `HoldEnd`, `HoldReached`, `ModifierTap`. For `Tap` and `MultiTap`, `count` is the number of consecutive taps.

### Mouse

| Event          | Fields                                             | When            |
|----------------|----------------------------------------------------|-----------------|
| `Mouse`        | `action`, `button`, `mods`, `x`, `y`, `col`, `row` | Every report    |
| `MouseGesture` | `kind`, `mouse`, `count`, `dx`, `dy`, `velocity`   | See kinds below |

`Mouse` actions: `Press`, `Release`, `Drag`, `Hover`, `Scroll`, `Leave`. Buttons: `Left`, `Middle`, `Right`, `None`, `WheelUp`, `WheelDown`, `WheelLeft`, `WheelRight`, `Aux8` to `Aux11`. `x` and `y` are pixels, `col` and `row` are cells.

`MouseGesture` kinds: `Click` (`count` is 1, 2, 3…), `DragStart`, `DragMove`, `DragEnd`, `Enter`, `HoverDwell`, `HoverEnd`, `Motion`, `Scroll` (`count` is the number of lines), `Swipe`, `Chord` (`count` is the number of buttons held), `LongPress`. `direction` gives `Left`, `Right`, `Up` or `Down` from `dx` and `dy`.

### Terminal

| Event         | Fields                                 | When                                 |
|---------------|----------------------------------------|--------------------------------------|
| `Resize`      | `rows`, `cols`, `width`, `height`      | The window was resized               |
| `Focus`       | `gained`                               | Focus changed                        |
| `Visibility`  | `visible`                              | The window was minimised or restored |
| `ColorScheme` | `dark`                                 | Light or dark mode changed           |
| `Paste`       | `mimes`, `primary`, `password`, `text` | The user pasted                      |

### Protocols

| Event          | Fields                                                                    | When                                                                   |
|----------------|---------------------------------------------------------------------------|------------------------------------------------------------------------|
| `Notification` | `kind`, `id`, `button`, `untracked`                                       | A notification was `Activated`, a `Button` was clicked, or it `Closed` |
| `Drop`         | `kind`, `col`, `row`, `x`, `y`, `operations`, `mimes`                     | A drag `Move`s over the window, `Leave`s, or `Land`s                   |
| `Drag`         | `kind`, `col`, `row`, `x`, `y`, `index`, `operation`, `canceled`, `error` | See kinds below                                                        |
| `Ack`          | `image`, `number`, `placement`, `message`                                 | A graphics reply nobody was waiting for                                |

`Drag` kinds: `Gesture`, `Started`, `Accepted`, `Action`, `Dropped`, `Finished`, `DataRequest`, `FileRequest`, `Error`.

## API

### Lifecycle and output

| Method                                                           | Returns                                     |
|------------------------------------------------------------------|---------------------------------------------|
| `Term.open(config, input = STDIN, output = STDOUT) { \|term\| }` | The block's value                           |
| `Term.new(config, input, output)`                                | A `Term` you must `close`                   |
| `close`, `closed?`                                               |                                             |
| `events`                                                         | `Channel(Term::Event)`                      |
| `features`                                                       | `Term::Feature` flags                       |
| `print(*objects)`, `<<(object)`                                  |                                             |
| `suspend`, `resume`                                              | Leave and re-enter the terminal modes       |
| `refresh`                                                        | Re-read the window size and emit a `Resize` |
| `Term.restore`, `Term.suspend`, `Term.resume`, `Term.refresh`    | The same for every open `Term`              |
| `supports?(mode)`                                                | `Bool?` for a DEC private mode              |
| `window_size`, `cell_size`                                       | `Term::Size?` in pixels                     |
| `query_visibility`, `query_color_scheme`                         | Nothing; the answer arrives as an event     |

### Pointer shape

```crystal
term.pointer = :pointer
term.push_pointer(:wait)
term.pop_pointer
term.reset_pointer
term.pointer                      # => "pointer", or nil when none is set
term.pointer_support(:grab, :zoom_in)  # => [true, false]
```

`Term::Shape` holds the thirty CSS-derived names, from `Alias` to `ZoomOut`. `pointer(which)` accepts `:current`, `:default` or `:grabbed`.

### Colors

```crystal
term.push_colors
term.color("foreground", "green")
term.color(1, Term::Color.rgb(255, 0, 128))
term.dynamic_color("cursor")
term.reset_color("background")
palette = term.colors("foreground", "cursor", 7)
palette.try &.["foreground"]      # => Term::Color or nil
term.confirm_color("background", "#102030")
term.pop_colors
```

- A key is a number `0` to `255` for the ANSI table, or a name such as `foreground`, `background`, `cursor`, `cursor_text`, `selection_background`, `selection_foreground`, `visual_bell`, `transparent_background_color1` to `7`.
- `colors` returns a `Term::Palette` with `[]`, `[]?`, `keys`, `size` and `unknown` (keys the terminal did not recognise). A color with no defined value is `nil`.
- `Term::Color` has 16-bit `red`, `green`, `blue` and a float `alpha`. `Color.parse` accepts `rgb:`, `#hex`, `rgbi:`, an `@alpha` suffix and 658 color names.

### Clipboard

```crystal
term.copy("hello")
term.clipboard_write({"text/html" => "<b>hi</b>".to_slice, "text/plain" => "hi".to_slice})
term.clipboard_mimes                          # => ["text/plain", "image/png"]
term.clipboard_read("text/plain").try(&.text)
File.open("clip.png", "w") { |file| term.clipboard_read("image/png", into: file) }
```

Handling a paste:

```crystal
when Term::Paste
  text = term.clipboard_read(event, "text/plain").try(&.text)
```

- `copy` and `clipboard_write` return a `Term::Status`: `Done`, or `EIO`, `EINVAL`, `ENOSYS`, `EPERM`, `EBUSY`, `EFBIG`.
- `clipboard_read` returns a `Term::Clipboard` with `status`, `done?`, `data` (a hash of MIME type to bytes) and `text`.
- Pass `primary: true` for the primary selection. Item values may be `Bytes` or an `IO`. With `into:`, data is streamed to the sink and `data` is empty.

### Graphics

```crystal
png = File.read("logo.png").to_slice
term.image(Term::Pixels.png(png), id: 1, placement: Term::Placement.new(columns: 20))
term.place(id: 1, placement: Term::Placement.new(id: 2, z: -1))
term.delete_images(:id, id: 1, free: true)
term.supports_graphics?
```

| Method                                                                                                   | Returns                      |
|----------------------------------------------------------------------------------------------------------|------------------------------|
| `image(pixels, id:, number:, placement:, quiet:, transient:)`                                            | `Term::Ack?`                 |
| `place(id:, number:, placement:, quiet:)`                                                                | `Ack?`                       |
| `delete_images(target, free:, id:, number:, placement:, x:, y:, z:)`                                     |                              |
| `frame(pixels, id:, number:, x:, y:, base:, edit:, gap:, replace:, background:, quiet:)`                 | `Ack?`                       |
| `animate(id:, number:, state:, current:, loops:, target:, gap:, quiet:)`                                 | Nothing                      |
| `compose(source, target, id:, number:, width:, height:, source_x:, source_y:, x:, y:, replace:, quiet:)` | `Ack?`                       |
| `image_query(pixels, id: 31)`                                                                            | `Ack?`                       |
| `supports_graphics?`                                                                                     | `Bool`                       |
| `Term.placeholder(id, columns, rows, placement = 0, compact: false)`                                     | `Array(String)`, one per row |

- **Pixel data** is a `Term::Pixels`: `Pixels.png(data)`, `Pixels.rgb(data, width, height)`, `Pixels.rgba(data, width, height)` take `Bytes` or an `IO`, with `compress: true` for zlib. `Pixels.at(path, medium)` sends a file, temp file or shared memory name; `Pixels.temp(data)` and `Pixels.shared(data)` create one for you.
- **Layout** is a `Term::Placement`: `id`, `x`, `y`, `width`, `height` (source rectangle), `offset_x`, `offset_y`, `columns`, `rows`, `z`, `hold_cursor`, `placeholder`, `parent`, `parent_placement`, `shift_x`, `shift_y`.
- **Replies.** A call waits for the terminal's `Ack` only when you give an `id` or `number` and leave `quiet` at `:none`. `Ack` has `ok?`, `error`, `image`, `number` and `placement`.
- **`animate` never waits**, because terminals do not acknowledge it on success. Errors arrive as `Ack` events.
- **Delete targets:** `Visible`, `Id`, `Number`, `Cursor`, `Frames`, `Cell`, `CellZ`, `Range`, `Column`, `Row`, `Z`. `free: true` also frees the stored data.
- **Placeholders** are limited to 297 rows and columns.

### Desktop notifications

```crystal
id = term.notify("Build finished", "2 warnings", buttons: ["Open", "Dismiss"], report: true)
term.close_notification(id)
```

| Method                                                  | Returns                                                   |
|---------------------------------------------------------|-----------------------------------------------------------|
| `notify(title, body = "", **options)`, `notify(notice)` | The notification id                                       |
| `close_notification(id)`                                |                                                           |
| `notifications_alive`                                   | `Array(String)?`                                          |
| `notification_support`                                  | `Hash(String, Array(String))?`, or `nil` when unsupported |

Options are the fields of `Term::Notice`:

| Field              | Meaning                                                  |
|--------------------|----------------------------------------------------------|
| `id`               | Your own id; reuse it to update a notification           |
| `app`, `types`     | Application name and notification types, for filtering   |
| `icons`            | Icon names, first match wins                             |
| `icon`, `icon_key` | Icon image data, and a cache key so it is sent only once |
| `buttons`          | Button labels                                            |
| `sound`            | Sound name, such as `"silent"`                           |
| `urgency`          | `Low`, `Normal` or `Critical`                            |
| `expires`          | Auto-close after this span; zero means never             |
| `occasion`         | `Always`, `Unfocused` or `Invisible`                     |
| `focus`            | Focus the window on click (default `true`)               |
| `report`           | Send `Notification` events for clicks and buttons        |
| `closes`           | Send a `Notification` event when it closes               |

Ids and icon keys may contain only `a-z A-Z 0-9 _ - + .`; anything else raises `ArgumentError`.

### Drag and drop: receiving

```crystal
term.accept_drops("text/uri-list", "text/plain")

# in the event loop
when Term::Drop
  case event.kind
  when .move? then term.drop_reply(:copy, "text/plain")
  when .land?
    index = event.mimes.not_nil!.index!("text/plain") + 1
    text = term.drop_data(index).try(&.text)
    term.drop_finish(:copy)
  end
```

| Method                                              | Returns           |
|-----------------------------------------------------|-------------------|
| `accept_drops(*mimes, remote: false)`, `stop_drops` |                   |
| `drop_reply(operation, *mimes)`                     |                   |
| `drop_data(index, entry = 0, into:)`                | `Term::DropData?` |
| `drop_entry(handle, index, into:)`                  | `DropData?`       |
| `drop_close(handle)`                                |                   |
| `drop_save(index, entry, destination)`              | `Bool`            |
| `drop_finish(operation)`                            |                   |

- Indexes are 1-based positions in the `Drop` event's MIME list.
- `Term::Operation` is a flag set of `Copy` and `Move`; `Operation::None` rejects.
- `DropData` has `data`, `text`, `error`, `ok?`, `remote?`, `symlink?`, `directory?`, `handle`, `entries` and `uris`.
- With `remote: true`, files dropped from another machine can be fetched: request the `text/uri-list` type, and if `remote?` is true, use `drop_save(index, entry, destination)` to download entry `entry` of the list, including whole directory trees.

### Drag and drop: sending

```crystal
term.offer_drags

# in the event loop
when Term::Drag
  case event.kind
  when .gesture?
    term.drag_offer(Term::Operation::Copy, "text/plain")
    term.drag_presend(0, "dragged text".to_slice)
    term.drag_text(1, "T")
    term.drag_start
  when .data_request?
    term.drag_data(event.index, "dragged text".to_slice)
  end
```

| Method                                                                   | Returns                             |
|--------------------------------------------------------------------------|-------------------------------------|
| `offer_drags(remote: false)`, `stop_drags`                               |                                     |
| `drag_offer(operations, *mimes)`                                         |                                     |
| `drag_presend(index, data)`, `drag_data(index, data)`                    |                                     |
| `drag_image(number, data, format, width, height, opacity = 0)`           |                                     |
| `drag_text(number, text, numerator = 1, denominator = 1, opacity = 0)`   |                                     |
| `drag_show(index)`                                                       |                                     |
| `drag_start`                                                             | `String?`: `"OK"` or the error name |
| `drag_fail(index, name, description = nil)`                              |                                     |
| `drag_abort(name, description = nil)`, `drag_cancel`                     |                                     |
| `drag_files(paths)`                                                      | The uri-list text                   |
| `drag_path(index, path)`, `drag_entry(index, data, flag, parent, child)` |                                     |
| `dnd_support`, `supports_dnd?`                                           | `Hash(String, String)?`, `Bool`     |
| `Term.uri_list(paths)`, `Term.machine_id`                                | `String`, `String?`                 |

- MIME indexes are 0-based here; image numbers start at 1.
- Data may be `Bytes` or an `IO`.
- To drag files to another machine, call `drag_files(paths)`, pre-send the returned text as `text/uri-list`, and the terminal's file requests are answered for you.

## TTY and PTY

Low-level helpers, useful for tests or for driving another program on a pseudo-terminal.

`TTY` is a set of functions on a file descriptor:

| Function                  | Returns                                               |
|---------------------------|-------------------------------------------------------|
| `mode(fd)`                | `LibC::Termios?`, `nil` when `fd` is not a terminal   |
| `apply(fd, mode)`         | `Bool`                                                |
| `raw(mode)`, `raw?(mode)` | A raw copy; whether a mode is raw                     |
| `window(fd)`              | `TTY::Window?` with `rows`, `cols`, `width`, `height` |
| `resize(fd, window)`      | `Bool`                                                |
| `signal_group(signal)`    | `Bool`                                                |

`PTY` is a pseudo-terminal pair:

```crystal
pty = PTY.spawn("sh", ["-c", "stty size"], window: TTY::Window.new(24, 80))
puts pty.rest                          # "24 80\r\n"
puts pty.process.not_nil!.wait.exit_code
pty.close
```

| Member                                  | Meaning                                                                                                       |
|-----------------------------------------|---------------------------------------------------------------------------------------------------------------|
| `PTY.open(window = nil)`                | A pair with `master`, `slave` and `name`                                                                      |
| `PTY.spawn(command, args, env, window)` | Runs a command on its own session with the PTY as its controlling terminal; `process` is a standard `Process` |
| `window`, `window=`                     | The terminal size; changing it notifies the child                                                             |
| `mode`, `mode=`                         | The terminal settings                                                                                         |
| `<<(text)`                              | Write to the master                                                                                           |
| `rest`                                  | Read until the child hangs up                                                                                 |
| `close`                                 |                                                                                                               |

## Limitations

- **Verified against the protocol documents and kitty's source, not a running kitty.** The test suite plays the terminal's side itself.
- **macOS is untested; Windows is unsupported.**
- **Signal handlers are global.** See [Signals and job control](#signals-and-job-control).
- **`drop_save` trusts the terminal.** It creates symlinks with the target it is given, overwrites existing files, and leaves a partial tree behind on failure.
- **No multiplexer passthrough.** Under tmux the kitty protocols are not wrapped and will be swallowed.
- **Some data is held in memory:** compressed image data, notification icons, and clipboard reads and dropped data when no `into:` sink is given.
- **`PTY.spawn` uses an undocumented Crystal API** to adopt the forked child, which may change between Crystal releases.

## Development

Run the suite once:

```sh
crystal spec
```

The suite drives `Term` over pipes and real pseudo-terminals. The child-process examples read `/proc` and so run on Linux only.

Run it thoroughly before a release:

```sh
spec/run.sh
```

`spec/run.sh` builds the suite three ways (default, `-Dexecution_context` and `--release`) and, for each build, runs it in defined order, in random order with several seeds, and one example at a time. Isolated runs catch examples that only pass because of what ran before them. A failing run prints the tail of its output, including the seed for random-order runs, and the script exits non-zero.

| Variable  | Default | Effect                                                           |
|-----------|---------|------------------------------------------------------------------|
| `ONLY`    | all     | Run a single build: `default`, `execution_context` or `release`. |
| `REPEATS` | `3`     | Defined-order runs per build.                                    |
| `SEEDS`   | `5`     | Random-order runs per build.                                     |
| `LIMIT`   | `300`   | Seconds before a single run is killed as hung.                   |

```sh
ONLY=default SEEDS=20 spec/run.sh
```

Keep the spec file free of top-level local variables.  
They are visible inside every `describe` and `it` block, and on Crystal 1.21.1 a top-level `term` next to a top-level `config` made an example read the wrong `Term` inside a nested captured block.  
The child-process scenario lives in a method for that reason.