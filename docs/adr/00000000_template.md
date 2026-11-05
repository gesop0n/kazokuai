# ADR 0000: アーキテクチャ判断を記録する

## Status

Accepted

## Context

このリポジトリの設計判断が、コードと README 以外に残っていない。
後から「なぜこうしたか」を復元できない。

## Decision

重要な設計判断は Architecture Decision Record として
docs/adr/ に Markdown で残す。形式はNygard形式に従う。

## Consequences

### Pros
採用した案と捨てた理由を後から追える。

### Cons
判断のたびに短い文書が増える。
