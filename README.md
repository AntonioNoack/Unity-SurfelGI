# Unity - Surfel GI
This is the repository for the Unity implementation of my master thesis.
It uses DXR raytracing for better performance. This unfortunately is only available on GTX 1000 series and RTX series GPUs.

# Setting up DXR in a new project:
- go to Edit/Project Settings/Player/Other and add DX 12 as the primary graphics API for Windows
- go to Edit/Project Settings/Graphics and enable deferred rendering for all profiles
- add the mathematics package