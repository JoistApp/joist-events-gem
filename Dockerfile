FROM 333592532126.dkr.ecr.us-east-1.amazonaws.com/joist-ruby-base:3.3.7-slim AS base

FROM base AS build

USER root

ARG CODEARTIFACT_AUTH_TOKEN
RUN test -n "$CODEARTIFACT_AUTH_TOKEN" || (echo "ERROR: CODEARTIFACT_AUTH_TOKEN build arg is required" && exit 1)

ENV APP_HOME /src
RUN mkdir -p "$APP_HOME/lib/joist/events"
WORKDIR $APP_HOME

COPY Gemfile* *.gemspec $APP_HOME/
COPY lib/joist/events/version.rb $APP_HOME/lib/joist/events/

RUN CODEARTIFACT_AUTH_TOKEN_ESCAPED=$(ruby -ruri -e 'puts URI.encode_www_form_component(ENV["CODEARTIFACT_AUTH_TOKEN"] || "")') \
  && bundle config set --local "https://jst-hub-artifacts-333592532126.d.codeartifact.us-east-1.amazonaws.com/ruby/jst-private-packages" "aws:${CODEARTIFACT_AUTH_TOKEN_ESCAPED}" \
  && bundle install -j 4 \
  && bundle config unset --local "https://jst-hub-artifacts-333592532126.d.codeartifact.us-east-1.amazonaws.com/ruby/jst-private-packages"
