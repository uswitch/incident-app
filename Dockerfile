FROM ruby:2.6

WORKDIR /usr/src/app

RUN gem install bundler:2.0.2

COPY Gemfile Gemfile.lock ./

RUN bundle config --global frozen 1 \
 && bundle install

COPY . .

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "9292"]
