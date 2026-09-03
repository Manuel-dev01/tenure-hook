# This folder is the published website, not documentation

GitHub Pages serves <https://manuel-dev01.github.io/tenure-hook/> from `main` + `/docs`. Branch-based
Pages publishing supports only the repository root or `/docs`, so the name is imposed by GitHub
rather than chosen. The project's documentation is in the repository root: `README.md`,
`ARCHITECTURE.md`, `DEMO.md`, `VERIFY.md`, and `analysis/`.

| file | what it is |
|---|---|
| `index.html` | the landing page |
| `app.html` | the demonstration app, reading live Sepolia state |
| `deployments.json` | the single source for contract addresses; the app fetches it |
| `.nojekyll` | disables Jekyll processing, so files are served exactly as committed |

Editing anything here changes the live site on the next push to `main`.
