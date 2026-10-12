# Menu bar widget

On macOS 14 or later, choose **Meno → Menu bar actions** in Edit Widgets on the desktop or in Notification Center. The medium widget provides **Show icons**, **Hide icons**, **Zen on** and **Zen off** links.

Edit the widget to enter the exact names of up to two scenes saved in Meno. Scene links apply those scenes through the same `meno://scene/...` handler as Shortcuts. If you rename or delete a scene, update the widget's configured name. Empty scene slots open Settings → Scenes. Deleted or unmatched scenes show Meno's existing error toast.

This first version is an action panel. It does not display an inferred current scene or Zen state. It does not read the app's preferences, request Accessibility permission or move menu bar items itself. Clicking opens Meno, which performs the operation with its existing permissions and error handling. When Accessibility is unavailable, grant it in Meno's Permissions page.

The app and MenoCore remain SwiftPM targets. `scripts/build-widgets.sh` generates a separate extension project with pinned XcodeGen 2.44.1, builds the universal extension when requested, embeds it, and signs it before `build-app.sh` signs the host. No App Group or new Apple provisioning capability is used for this link-only version.

CI checks embedding, matching versions, code signatures and pluginkit registration. Before publishing, install the Developer ID signed build on a Mac, add the widget, test all four built-in actions and both scene links with Meno running and stopped, then check missing-permission and deleted-scene behavior. The gallery rendering and actual clicks remain manual macOS acceptance checks; a successful Linux test does not prove them.
