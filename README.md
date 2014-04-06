# Kaede

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
- systemd
- recpt1
- b25
- [statvfs](https://github.com/eagletmt/misc/blob/master/statvfs.c)
- [clean-ts](https://github.com/eagletmt/misc/tree/master/mm/clean-ts)
- assdumper

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

## Contributing

1. Fork it ( https://github.com/eagletmt/kaede/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
