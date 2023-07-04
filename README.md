# Unity - Surfel GI
This is the repository for the Unity implementation of [my master thesis](https://anionoa.phychi.com/report/MasterThesis.pdf).
It uses DXR raytracing for better performance. This unfortunately is only available on [recent GPUs](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@14.0/manual/Ray-Tracing-Getting-Started.html) like Nvidia GTX 1000 series, Nvidia RTX series and AMD RX 6000 series .

# Setting up DXR in a new project:
- go to Edit/Project Settings/Player/Other and add DX 12 as the primary graphics API for Windows
- go to Edit/Project Settings/Graphics and enable deferred rendering for all profiles

# Additional setup for surfels:
- add the mathematics package
- open Edit/Project Settings/Script Execution Order and make sure your camera controller is executed before the DXRCamera script