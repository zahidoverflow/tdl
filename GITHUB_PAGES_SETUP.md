# Enable GitHub Pages

To make the one-liner work, you need to enable GitHub Pages:

## Steps:

1. Go to your repo: https://github.com/zahidoverflow/tdl

2. Click **Settings** (top menu)

3. Scroll down to **Pages** (left sidebar, under "Code and automation")

4. Under **Source**, select:
   - Source: **Deploy from a branch**
   - Branch: **master** 
   - Folder: **/docs**

5. Click **Save**

6. Wait 1-2 minutes for deployment

7. Test the URL: https://zahidoverflow.github.io/tdl

It should return a small PowerShell bootstrap script (used by the one-liner).

## Testing

Once GitHub Pages is live, test the one-liner in PowerShell:

```powershell
irm https://zahidoverflow.github.io/tdl | iex
```

✅ Done!
