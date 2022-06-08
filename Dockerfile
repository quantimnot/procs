# Used for locally testing the Linux backend.

FROM nimlang/nim:latest-alpine-regular

## install dependencies
# RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev netcat-openbsd

## set working directory
WORKDIR /usr/src/app

## add user
# RUN addgroup --system nim && adduser --system --group nim
# RUN chown -R nim:nim /usr/src/app && chmod -R 755 /usr/src/app

## Nim environment
# ENV NIM_ENV=production
# ENV NIMBLE_DIR=/home/nim/.nimble
# ENV PATH=$PATH:/home/nim/.nimble/bin

## copy entrypoint, make executable
# COPY ./entrypoint.sh .
# RUN chmod +x entrypoint.sh

## install dependencies, bundle assets, compile
# RUN nimble refresh && nimble install nimassets jester
COPY . .
# RUN nimassets -d=public -o=src/views/assetsfile.nim && \
        # nimble c -d:release src/urlShortener

## switch to non-root user
# USER nim

# CMD ["./src/urlShortener"]
