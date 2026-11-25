# Map My Argument

Build your argument like a building, then stress-test it.

- Your **position** is the roof. Each **reason** is a pillar; better-supported pillars are wider, and the beam sags over weak ones.
- **Sources** are posts under a pillar: one is weak (I), two moderate (II), three independent ones are cross-braced (IXI). A source you don't trust holds up nothing.
- **Supporting points** are blocks under a pillar. A **belief cloud** holds up what you believe without evidence.
- **Termites** eat claims you're very sure of but said you haven't looked into.
- Red arrows are **counter-arguments** you haven't answered.
- Stress tests: **wind** blows away belief clouds, an **earthquake** finds the cracks, and an **opponent** (Progressive, Conservative, Libertarian, Scientist, Skeptic) throws out the sources it doesn't trust, knocks out the premises you said it would reject, then pushes on whatever you're unsure of.
- **Compare with a friend**: share a code, they rate each claim, and you see where you agree, where your trust in sources differs, and where to start talking (foundations first).

There are two versions with the same rules:

| Folder | What |
|---|---|
| `web/` | The website. Plain HTML, CSS and JavaScript, no build step. Open `web/index.html` through any web server. |
| `MapMyArgument/`, `Packages/ArgumentKit/` | The iPhone app (SwiftUI, iOS 18+) and its tested logic. |

Maps stay on the device or in the browser. Sharing is by code (`MMA1.…`), which works between the website and the app in both directions.

`ENGINE.md` explains every number in the scoring.

## Running the website

```bash
cd MapMyArgument/web && python3 -m http.server 8000   # then open http://localhost:8000
node --test MapMyArgument/web/tests/*.test.mjs        # from the repo root
```

It is static, so any host works (GitHub Pages, Netlify, an S3 bucket) for mapmyargument.com.
