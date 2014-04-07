# Kaede
[![Build Status](https://api.travis-ci.org/eagletmt/kaede.svg)](https://travis-ci.org/eagletmt/kaede)
[![Coverage Status](https://coveralls.io/repos/eagletmt/kaede/badge.png)](https://coveralls.io/r/eagletmt/kaede)

Scheduler for recpt1 recorder using [Syoboi Calendar](http://cal.syoboi.jp/).

## Installation

Add this line to your application's Gemfile:

    gem 'kaede'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kaede

## Usage
### Requirements
- sqlite3
- redis
- systemd
- recpt1
- b25
- [statvfs](https://github.com/eagletmt/eagletmt-recutils/tree/master/statvfs)
- [clean-ts](https://github.com/eagletmt/eagletmt-recutils/tree/master/clean-ts)
- [assdumper](https://github.com/eagletmt/eagletmt-recutils/tree/master/assdumper)

Some of them should be optional, though.

### Setup
```sh
cp kaede.rb.sample kaede.rb
vim kaede.rb

cp kaede.service.sample kaede.service
vim kaede.service

sudo cp kaede.service /etc/systemd/system/kaede.service
sudo systemctl enable kaede.service
sudo systemctl start kaede.service
```

Add your available channels.

```sh
kaede add-channel MX -c kaede.rb --recorder 16 --syoboi 19
kaede add-channel BS11 -c kaede.rb --recorder 211 --syoboi 128
...
```

Add your favorite anime tids.

```sh
kaede add-tid -c kaede.rb 3331
...
```

### Operations
Update programs and schedules. It supposed to be run periodically (by cron or systemd.timer).

```sh
kaede update -c kaede.rb
```

List schedules (needs improvements).

```sh
sudo systemctl kill -s USR1 --kill-who main kaede.service
sudo journalctl -u kaede.service
```

Reload schedules (usually not needed).

```sh
sudo systemctl kill -s HUP --kill-who main kaede.service
```

## What recorder does
1. Post the earlier tweet (optional).
2. Record the program into `record_dir` by recpt1.
    - At the same time, decode into `cache_dir` by b25.
    - At the same time, dump ass into `cache_dir` by assdumper.
3. Post the later tweet (optional).
4. Clean the recorded TS (in `cache_dir`) into `cabinet_dir`.
5. Move dumped ass (in `cache_dir`) into `cabinet_dir`.
6. Enqueue the filename into `redis_queue`.
    - Use it as an encoder queue.
    - My usage: https://github.com/eagletmt/eagletmt-recutils/tree/master/encoder

## Contributing

1. Fork it ( https://github.com/eagletmt/kaede/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
