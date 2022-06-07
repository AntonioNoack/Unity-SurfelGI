using UnityEngine;
// using UnityEngine.Rendering.HighDefinition;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

abstract class CustomPass {
    protected abstract void Setup(ScriptableRenderContext renderContext, CommandBuffer cmd);
    protected abstract void Execute(CustomPassContext ctx);
    protected abstract void Cleanup();
}

class CustomPassContext {

}

class TestPass : CustomPass {

    public DXRCamera dxrCamera;

    // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
    // When empty this render pass will render to the active camera render target.
    // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
    // The render pipeline will ensure target setup and clearing happens in an performance manner.
    protected override void Setup(ScriptableRenderContext renderContext, CommandBuffer cmd) {
        // Setup code here
        if(dxrCamera != null){
            // dxrCamera.Init();
        }
    }

    protected override void Execute(CustomPassContext ctx) {
        // Executed every frame for all the camera inside the pass volume.
        // The context contains the command buffer to use to enqueue graphics commands.
        if(dxrCamera != null){
            // dxrCamera.Update();
            // dxrCamera.OnRenderImage(null, null);
        }
    }

    protected override void Cleanup() {
        // Cleanup code
         if(dxrCamera != null){
            // dxrCamera.Release();
        }
    }
}