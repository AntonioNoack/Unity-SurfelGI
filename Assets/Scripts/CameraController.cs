using UnityEngine;

public class CameraController : MonoBehaviour {

    public Vector3 velocity;
    public Vector2 rotation;
    public float moveSpeed = 10f;
    public float rotSpeed = 10f;
    public float friction = 5f;

    public const int RIGHT_MOUSE_BUTTON = 1;

    void Update() {
        float dt = Time.deltaTime;
        Vector3 acceleration = new Vector3();
        // collect inputs
        if(Input.GetKey("w")) acceleration.z++;
        if(Input.GetKey("s")) acceleration.z--;
        if(Input.GetKey("a")) acceleration.x--;
        if(Input.GetKey("d")) acceleration.x++;
        if(Input.GetKey("q") || Input.GetKey("left shift")) acceleration.y--;
        if(Input.GetKey("e") || Input.GetKey("space")) acceleration.y++;
        moveSpeed *= Mathf.Pow(1.05f, Input.mouseScrollDelta.y);
        acceleration *= moveSpeed;
        // mouse movement
        if(Input.GetMouseButton(RIGHT_MOUSE_BUTTON)){
            Vector2 mouse = new Vector2(Input.GetAxis("Mouse X"), Input.GetAxis("Mouse Y"));
            rotation += mouse * rotSpeed;
            rotation.y = Mathf.Clamp(rotation.y, -90f, 90f);// clamp up-down rotation
        }
        transform.localRotation = Quaternion.AngleAxis(rotation.x, Vector3.up) * Quaternion.AngleAxis(rotation.y, Vector3.left);
        float dt2 = Mathf.Clamp(friction * dt, 0f, 1f);
        velocity = velocity * (1f - dt2) + acceleration * dt2;
        float vl = velocity.magnitude;
        if(vl > 0.001f * moveSpeed){
            if(vl > moveSpeed){
                velocity *= (moveSpeed / vl);
            }
            Vector3 movement = velocity * dt;
            // transform movement into global space
            transform.Translate(movement, Space.Self);
        }
        if(Input.GetKeyDown(KeyCode.Escape)) {// for builds
            Application.Quit();
        }
    }
}
