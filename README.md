# Research Consensus

Omarchy bar widget that searches [Europe PMC](https://europepmc.org) for
meta-analyses and systematic reviews on a topic, surfacing the actual
scientific consensus instead of one-off studies.

## Features

- Two-tier search: meta-analyses & systematic reviews first, other studies
  as a fallback for topics without dedicated reviews yet
- No manual journal blocklist — Europe PMC only indexes MEDLINE/PMC and
  other curated agency sources, so restricting the search to it *is* the
  quality filter
- Shows title, journal, year, citation count, and abstract for each result
- Opens the DOI (or Europe PMC article page) in your default browser

## Keyboard shortcuts

Inside the panel:

- `enter`: run the search, or open the highlighted result if the query
  hasn't changed
- `up` / `down`: move the selection
- `esc`: close

## Requirements

- `curl` on `PATH`
- No API key needed — Europe PMC's REST API is free and keyless

## Add to the bar

This is a third-party plugin. Install it with:

```bash
omarchy plugin add https://github.com/Fireez30/omarchy-consensus.git --enable
```

Move it with `omarchy bar move faeres.omarchy-consensus` if you want it somewhere
other than the default placement.
