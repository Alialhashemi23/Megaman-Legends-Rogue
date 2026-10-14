# Retroid Pocket 5 test checklist (phases 4/5)

Short owner checklist for the first hardware pass. Use test-signed local APKs
only; nothing is published. Install with `adb install -r` or the file manager.
Never uninstall to update (that erases saves and the Keystore session).

1. **Install the older build** (code 3) and note Guest digs/Zenny on the title.
2. **Sign in:** Account → Sign In → approve the code in the browser → switch
   back to the game. Expect your cloud digs/Zenny and status "Synced".
3. **Restart:** close the app from recents, reopen. Expect sign-in retained
   without a new code.
4. **Offline boot:** Wi-Fi off, reopen, press Start Dig → "Restoring your
   account". Choose Play as Guest and play briefly. Wi-Fi on → Account → Sign In
   restores the saved session without a new code (needs the readiness fix
   build). On older builds, Guest here signs you out.
5. **Earn and spend:** finish one account dig and buy one Workshop circuit. Check
   the same totals in the browser and on Windows.
6. **Controls:** controller-only through Title, Account, Workshop, Options,
   Credits and the update prompt; Back/B returns each time.
7. **Sleep/reconnect:** sleep the device on the title and in an online lobby;
   wake. Expect the lobby to rejoin and pending progress to sync.
8. **Co-op:** one dig with a browser and Windows player (late join, host leave).
9. **Update in place:** install the newer build over the old one. Expect the
   same Guest and account progress, settings and sign-in.
10. **Installer edge cases (optional):** cancel the install, sleep mid-download,
    low storage. The old app must keep working.

Also note frame rate, heat and battery over a full three-descent run, text
readability at 5.5", and whether the browser download page opened from the
update prompt (only once update hosting is deliberately enabled).
