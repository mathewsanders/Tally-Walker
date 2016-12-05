# Using Tally in Swift Playgrounds

Attempting to import Tally in a playground you'll get the following error:
_No such module 'Tally'_

To get a Swift playground and framework to work with each other, they need to
exist within the same workspace.

Instead of opening a playground file directly:

1. Open `Playgrounds.xworkspace` from the playgrounds folder
2. Build project (⌘B)
3. That's it! Tally should now be available in this playground
