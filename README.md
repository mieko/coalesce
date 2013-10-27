# Coalesce

`coalesce` is a generic library for combining and aggregating ruby objects.
This can be a pretty complicated problem, and has a bunch of edge-cases.



## Installation

Add this line to your application's Gemfile:

    gem 'coalesce', github: 'mieko/coalesce'

And then execute:

    $ bundle

## Usage

```ruby

Coalesce::Grouper(PublicActivity::Activities.all.limit(100)) do
  rule :accept_and_close do
    key 'ticket.accept', 'ticket.close'

    combine :id,  with: :array
    combine :key, with: :smart_key
  end
end

```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
