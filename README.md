# Unity - Surfel GI
This is the repository for the Unity implementation of my master thesis.
It uses DXR raytracing for better performance. This unfortunately is only available on [recent GPUs](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@14.0/manual/Ray-Tracing-Getting-Started.html) like Nvidia GTX 1000 series, Nvidia RTX series and AMD RX 6000 series .

## Simple Branch
This branch specifically is a demo of Surfel GI without poisson reconstruction or any complicated path tracing.
This hopefully makes it easier to understand.

I could simplify it even more by removing features like path-tracing pixels, movable surfels, fib-sphere-distribution, and visualizations.