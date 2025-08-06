# Section 5: Secure Execution Sandbox for Python Tools

This section defines the architecture and implementation of the secure sandbox, a critical component of the Qilbee OS security model. Its purpose is to provide a strongly isolated environment for the execution of Python tool code, mitigating the risks associated with running potentially untrusted, third-party plugins.

## 5.1. Rationale for Process-Level Isolation

The execution of arbitrary Python code, especially from plugins developed by external parties, introduces a significant security vulnerability to the host system. Relying on pure Python mechanisms for sandboxing is fraught with peril. The language's dynamic and introspective nature makes it exceedingly difficult to create a truly inescapable jail. Numerous historical attempts have failed, and there are many well-documented techniques for bypassing such restrictions, often through accessing low-level object attributes (`__dunder__` methods) to break out of the restricted scope.

The official Python documentation itself issues a stark warning that its auditing hooks "are not suitable for implementing a 'sandbox'" and can be "trivially disable[d] or bypass[ed]" by malicious code.

Given these inherent weaknesses, a robust security model cannot be built at the language level. Instead, Qilbee OS must enforce isolation at a lower, more fundamental level: the operating system process. By leveraging kernel-level security primitives, the system can create a much stronger and more reliable boundary between the executing tool code and the host OS, preventing unauthorized access to the filesystem, network, and other system resources.

### Python Sandbox Vulnerabilities Example

```python
# Example of how Python sandboxing can be bypassed
# These techniques make pure Python sandboxing unreliable

# Breaking out via object introspection
def escape_via_builtins():
    # Access builtins through various paths
    builtins = ().__class__.__bases__[0].__subclasses__()[104].__init__.__globals__['builtins']
    return builtins

# Breaking out via exception handling
def escape_via_exception():
    try:
        raise Exception
    except:
        frame = sys.exc_info()[2].tb_frame
        return frame.f_back.f_globals

# These demonstrate why OS-level isolation is necessary
```

## 5.2. Sandbox Implementation: nsjail for Granular System Call and Filesystem Control

The Python Tool Execution Engine will utilize the `nsjail` tool to create and manage the secure sandbox for every tool execution.

This selection is based on nsjail's design as a lightweight yet exceptionally powerful process isolation tool for Linux. It is built directly upon a suite of modern Linux kernel security features, including namespaces (PID, Mount, Network, etc.), resource limits (cgroups, rlimits), and, most critically, seccomp-bpf syscall filtering. This combination of features provides the precise, granular control necessary to build a highly restrictive and secure sandbox.

### nsjail Key Features

With nsjail, the Execution Engine can programmatically define a strict security policy for each tool execution. This policy can:

- **Network Isolation**: Completely isolate the tool's network stack
- **Filesystem Control**: Provide a private, temporary, and heavily restricted view of the filesystem via chroot
- **Resource Limits**: Enforce strict limits on CPU time and memory allocation to prevent denial-of-service attacks  
- **Syscall Filtering**: Apply a seccomp-bpf filter to explicitly whitelist only the specific system calls the process is permitted to make

The ability to control execution at the syscall level provides the strongest possible form of confinement. Furthermore, nsjail's use of a ProtoBuf-based configuration format makes it particularly well-suited for programmatic generation and management from a controlling application like the Qilbee Execution Engine.

### nsjail Installation and Setup

```bash
# Install nsjail on Ubuntu
sudo apt-get update
sudo apt-get install -y nsjail

# Verify installation
nsjail --help
```

## 5.3. Programmatic Sandbox Management from the Execution Engine

The Tool Execution Engine will be responsible for the entire lifecycle of the sandboxing process. For each tool execution request it receives from the Orchestrator, it will perform the following sequence of operations:

### Sandbox Lifecycle Implementation

```python
import subprocess
import tempfile
import os
import json
import shutil
from pathlib import Path
from typing import Dict, Any, Optional
import asyncio

class SecureSandboxManager:
    def __init__(self, base_config_path: str = "/etc/qilbee/nsjail-default.cfg"):
        self.base_config_path = base_config_path
        self.sandbox_root = Path("/tmp/qilbee-sandboxes")
        self.sandbox_root.mkdir(exist_ok=True, mode=0o755)
    
    async def execute_tool_sandboxed(
        self, 
        tool_code: str, 
        tool_args: Dict[str, Any],
        timeout_seconds: int = 30,
        memory_limit_mb: int = 256
    ) -> Dict[str, Any]:
        """Execute tool code in a secure sandbox."""
        
        # 1. Configuration Generation
        sandbox_id = self._generate_sandbox_id()
        sandbox_dir = self.sandbox_root / sandbox_id
        
        try:
            # Create sandbox directory structure
            self._prepare_sandbox_environment(sandbox_dir)
            
            # Generate nsjail configuration
            config_path = self._generate_nsjail_config(
                sandbox_dir, timeout_seconds, memory_limit_mb
            )
            
            # 2. Script Preparation
            script_path = self._prepare_tool_script(
                sandbox_dir, tool_code, tool_args
            )
            
            # 3. Process Invocation
            result = await self._execute_nsjail_process(
                config_path, script_path, timeout_seconds
            )
            
            # 4. Artifact Collection
            artifacts = self._collect_artifacts(sandbox_dir)
            result["artifacts"] = artifacts
            
            return result
            
        finally:
            # 5. Cleanup
            self._cleanup_sandbox(sandbox_dir)
    
    def _generate_sandbox_id(self) -> str:
        """Generate unique sandbox identifier."""
        import uuid
        return f"sandbox_{uuid.uuid4().hex[:8]}"
    
    def _prepare_sandbox_environment(self, sandbox_dir: Path) -> None:
        """Create sandbox directory structure."""
        sandbox_dir.mkdir(exist_ok=True, mode=0o755)
        
        # Create required directories
        (sandbox_dir / "workspace").mkdir(exist_ok=True, mode=0o755)
        (sandbox_dir / "tmp").mkdir(exist_ok=True, mode=0o777)
        (sandbox_dir / "config").mkdir(exist_ok=True, mode=0o755)
    
    def _generate_nsjail_config(
        self, 
        sandbox_dir: Path, 
        timeout_seconds: int,
        memory_limit_mb: int
    ) -> Path:
        """Generate nsjail configuration file."""
        
        config_content = f"""
name: "qilbee-tool-sandbox"
description: "Secure sandbox for Qilbee OS tool execution"

mode: ONCE
hostname: "sandbox"

log_level: WARNING

time_limit: {timeout_seconds}

# Process limits
rlimit_as: {memory_limit_mb * 1024 * 1024}  # Address space limit
rlimit_cpu: {timeout_seconds}  # CPU time limit
rlimit_fsize: 16777216  # File size limit (16MB)
rlimit_nofile: 64  # Number of file descriptors

# Disable networking
clone_newnet: true

# Filesystem isolation
clone_newns: true
clone_newpid: true
clone_newipc: true
clone_newuts: true

# Mount configuration  
mount {{
    src: "/usr/bin/python3"
    dst: "/usr/bin/python3"
    is_bind: true
    rw: false
}}

mount {{
    src: "/usr/lib/python3"
    dst: "/usr/lib/python3"
    is_bind: true
    rw: false
}}

mount {{
    src: "/lib"
    dst: "/lib"
    is_bind: true
    rw: false
}}

mount {{
    src: "/lib64"
    dst: "/lib64"
    is_bind: true
    rw: false
}}

mount {{
    src: "{sandbox_dir}/workspace"
    dst: "/workspace"
    is_bind: true
    rw: true
}}

mount {{
    src: "{sandbox_dir}/tmp"
    dst: "/tmp"
    is_bind: true
    rw: true
}}

# Temporary filesystem for /dev
mount {{
    dst: "/dev"
    fstype: "tmpfs"
    rw: true
    options: "size=1M,nr_inodes=1024"
}}

# Create essential /dev entries
mount {{
    src: "/dev/null"
    dst: "/dev/null"
    is_bind: true
    rw: true
}}

mount {{
    src: "/dev/zero"
    dst: "/dev/zero"
    is_bind: true
    rw: true
}}

mount {{
    src: "/dev/urandom"
    dst: "/dev/urandom"
    is_bind: true
    rw: true
}}

# Seccomp-bpf syscall filtering
seccomp_string: "POLICY a {{ ALLOW {{ write, read, openat, close, brk, fstat, lseek, mmap, rt_sigaction, rt_sigprocmask, ioctl, access, arch_prctl, set_tid_address, set_robust_list, rseq, mprotect, munmap, getrandom, exit_group }} }} DEFAULT KILL"

# User/group configuration  
inside_user: "nobody"
inside_group: "nogroup"

exec_bin {{
    path: "/usr/bin/python3"
    arg: "/workspace/tool_script.py"
}}
"""
        
        config_path = sandbox_dir / "nsjail.cfg"
        with open(config_path, 'w') as f:
            f.write(config_content)
        
        return config_path
    
    def _prepare_tool_script(
        self, 
        sandbox_dir: Path, 
        tool_code: str, 
        tool_args: Dict[str, Any]
    ) -> Path:
        """Prepare the Python script to be executed."""
        
        script_content = f"""#!/usr/bin/python3
import json
import sys
import traceback

# Tool arguments
TOOL_ARGS = {json.dumps(tool_args, indent=2)}

# Tool code
try:
    # Execute the tool code
    {tool_code}
    
    # If tool code defines a main function, call it
    if 'main' in locals():
        result = main(TOOL_ARGS)
        print(json.dumps({{"success": True, "result": result}}))
    else:
        print(json.dumps({{"success": True, "result": "Tool executed successfully"}}))

except Exception as e:
    error_info = {{
        "success": False,
        "error": str(e),
        "traceback": traceback.format_exc()
    }}
    print(json.dumps(error_info))
    sys.exit(1)
"""
        
        script_path = sandbox_dir / "workspace" / "tool_script.py"
        with open(script_path, 'w') as f:
            f.write(script_content)
        
        os.chmod(script_path, 0o755)
        return script_path
    
    async def _execute_nsjail_process(
        self, 
        config_path: Path, 
        script_path: Path,
        timeout_seconds: int
    ) -> Dict[str, Any]:
        """Execute the nsjail process."""
        
        cmd = [
            "nsjail", 
            "--config", str(config_path),
            "--really_quiet"
        ]
        
        try:
            # Execute with timeout
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(), 
                    timeout=timeout_seconds + 5  # Add buffer to nsjail timeout
                )
                
                return {
                    "success": process.returncode == 0,
                    "stdout": stdout.decode('utf-8', errors='replace'),
                    "stderr": stderr.decode('utf-8', errors='replace'),
                    "exit_code": process.returncode
                }
                
            except asyncio.TimeoutError:
                # Kill the process if it times out
                process.kill()
                await process.wait()
                
                return {
                    "success": False,
                    "error": f"Tool execution timed out after {timeout_seconds} seconds",
                    "stdout": "",
                    "stderr": "",
                    "exit_code": -1
                }
                
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to execute sandbox: {str(e)}",
                "stdout": "",
                "stderr": "",
                "exit_code": -1
            }
    
    def _collect_artifacts(self, sandbox_dir: Path) -> List[Dict[str, Any]]:
        """Collect any artifacts generated by the tool."""
        artifacts = []
        workspace_dir = sandbox_dir / "workspace"
        
        if not workspace_dir.exists():
            return artifacts
        
        for file_path in workspace_dir.rglob("*"):
            if file_path.is_file() and file_path.name != "tool_script.py":
                try:
                    stat = file_path.stat()
                    artifacts.append({
                        "name": file_path.name,
                        "relative_path": str(file_path.relative_to(workspace_dir)),
                        "size": stat.st_size,
                        "created_at": stat.st_ctime,
                        "modified_at": stat.st_mtime
                    })
                except Exception as e:
                    # Skip files we can't read
                    continue
        
        return artifacts
    
    def _cleanup_sandbox(self, sandbox_dir: Path) -> None:
        """Clean up sandbox directory and all contents."""
        try:
            if sandbox_dir.exists():
                shutil.rmtree(sandbox_dir)
        except Exception as e:
            # Log cleanup error but don't raise
            print(f"Warning: Failed to cleanup sandbox {sandbox_dir}: {e}")
```

## 5.4. Default Sandbox Profile and Security Policy

To enforce a principle of least privilege, all tools will be executed with a default, highly restrictive nsjail security profile. Any deviation from this baseline must be explicitly declared in the tool's plugin manifest and approved by an administrator via the RBAC system.

### Default Security Restrictions

The default profile will enforce the following restrictions:

#### Network Isolation
- All network namespaces will be disabled (`clone_newnet = true`)
- The tool will have no access to any network interfaces, including the loopback device
- This effectively prevents all network communication

#### Filesystem Isolation  
- The sandbox will be chrooted into a minimal, read-only root filesystem
- The only writable location will be a temporary tmpfs mount at `/tmp`, which is destroyed when the sandbox terminates
- Bind mounts will be used to selectively and read-only expose the specific Python libraries required for the tool to run

#### Resource Limits
Strict resource limits (rlimit) will be applied to prevent resource exhaustion:
- **CPU Time**: 30 seconds
- **Memory (Address Space)**: 256 MB  
- **Number of Processes**: 1 (no fork)
- **File Size**: 16 MB

#### System Call Filtering
A stringent seccomp-bpf filter will be applied. The policy will be to deny all system calls by default, and then explicitly allow only the minimal set required for a basic Python script to execute. This allowlist includes calls like:
- `read`, `write`, `openat`, `close`
- `mmap`, `brk`, `exit_group`
- `rt_sigaction`, `rt_sigprocmask`

But explicitly denies dangerous calls like:
- `socket`, `clone`, `ptrace`, `execve`

### Complete Default nsjail Configuration

```protobuf
# /etc/qilbee/nsjail-default.cfg
name: "qilbee-default-sandbox"
description: "Default secure sandbox for Qilbee OS tools"

mode: ONCE
hostname: "qilbee-sandbox"

log_level: WARNING

# 30 second execution time limit
time_limit: 30

# Resource limits
rlimit_as: 268435456      # 256MB address space
rlimit_cpu: 30            # 30 seconds CPU time
rlimit_fsize: 16777216    # 16MB file size limit
rlimit_nofile: 64         # File descriptor limit
rlimit_nproc: 1           # No process forking

# Complete isolation
clone_newnet: true        # Network namespace isolation
clone_newns: true         # Mount namespace isolation  
clone_newpid: true        # PID namespace isolation
clone_newipc: true        # IPC namespace isolation
clone_newuts: true        # UTS namespace isolation

# User isolation - run as nobody
inside_user: "nobody"
inside_group: "nogroup"

# Minimal Python runtime mounts (read-only)
mount {
    src: "/usr/bin/python3"
    dst: "/usr/bin/python3"
    is_bind: true
    rw: false
}

mount {
    src: "/usr/lib/python3"
    dst: "/usr/lib/python3"  
    is_bind: true
    rw: false
}

mount {
    src: "/lib/x86_64-linux-gnu"
    dst: "/lib/x86_64-linux-gnu"
    is_bind: true
    rw: false
}

# Working directory (read-write)
mount {
    dst: "/workspace"
    fstype: "tmpfs"
    rw: true
    options: "size=16M,nr_inodes=1024"
}

# Temporary directory
mount {
    dst: "/tmp"
    fstype: "tmpfs" 
    rw: true
    options: "size=16M,nr_inodes=1024"
}

# Essential /dev entries
mount {
    dst: "/dev"
    fstype: "tmpfs"
    rw: true
    options: "size=1M,nr_inodes=64"
}

mount {
    src: "/dev/null"
    dst: "/dev/null"
    is_bind: true
    rw: true
}

mount {
    src: "/dev/zero"
    dst: "/dev/zero"
    is_bind: true
    rw: true
}

mount {
    src: "/dev/urandom"
    dst: "/dev/urandom"
    is_bind: true
    rw: true
}

# Seccomp syscall filter - very restrictive allowlist
seccomp_string: "POLICY a { ALLOW { arch_prctl, brk, close, exit_group, fstat, getrandom, ioctl, lseek, mmap, mprotect, munmap, openat, read, rseq, rt_sigaction, rt_sigprocmask, set_robust_list, set_tid_address, write, access } } DEFAULT KILL"

# Python execution
exec_bin {
    path: "/usr/bin/python3"
    arg: "/workspace/script.py"
}
```

## 5.5. Execution of GUI Automation Tools

To enable Qilbee OS to control any tool or software installed within its own environment, the execution model for GUI automation tools must grant direct access to the host's display server. This approach provides maximum compatibility and control, but it represents a significant security trade-off that must be carefully managed.

### 5.5.1. Direct Execution Model

The Python Tool Execution Engine will execute all GUI automation commands (e.g., screenshot, mouse clicks, keyboard input) directly within the main Qilbee OS container's process space. These specific tools will **not** be run inside the nsjail sandbox described in previous sections. This is a necessary exception to the sandboxing policy, as tools like nsjail are designed to prevent the very access to host resources that GUI automation requires.

### GUI Tool Execution Implementation

```python
import subprocess
import tempfile
import base64
from PIL import ImageGrab
import pyautogui
from typing import Dict, Any

class GUIAutomationExecutor:
    def __init__(self):
        # Configure PyAutoGUI safety settings
        pyautogui.FAILSAFE = True
        pyautogui.PAUSE = 0.1
        
        # Detect display server type
        self.display_server = self._detect_display_server()
    
    def _detect_display_server(self) -> str:
        """Detect whether we're running on X11 or Wayland."""
        import os
        
        if os.environ.get('WAYLAND_DISPLAY'):
            return 'wayland'
        elif os.environ.get('DISPLAY'):
            return 'x11'
        else:
            return 'unknown'
    
    async def take_screenshot(self) -> Dict[str, Any]:
        """Take screenshot using appropriate method for display server."""
        try:
            if self.display_server == 'wayland':
                return await self._screenshot_wayland()
            else:
                return await self._screenshot_x11()
        except Exception as e:
            return {"error": f"Screenshot failed: {str(e)}"}
    
    async def _screenshot_x11(self) -> Dict[str, Any]:
        """Take screenshot on X11 using scrot."""
        try:
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_file:
                # Use scrot for X11 screenshots
                result = subprocess.run([
                    'scrot', tmp_file.name
                ], capture_output=True, text=True, timeout=5)
                
                if result.returncode == 0:
                    with open(tmp_file.name, 'rb') as img_file:
                        img_data = base64.b64encode(img_file.read()).decode()
                    
                    # Cleanup temp file
                    os.unlink(tmp_file.name)
                    
                    return {
                        "success": True,
                        "base64_image": img_data,
                        "format": "png"
                    }
                else:
                    return {"error": f"scrot failed: {result.stderr}"}
                    
        except Exception as e:
            return {"error": f"X11 screenshot error: {str(e)}"}
    
    async def _screenshot_wayland(self) -> Dict[str, Any]:
        """Take screenshot on Wayland using grim."""
        try:
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_file:
                # Use grim for Wayland screenshots
                result = subprocess.run([
                    'grim', tmp_file.name
                ], capture_output=True, text=True, timeout=5)
                
                if result.returncode == 0:
                    with open(tmp_file.name, 'rb') as img_file:
                        img_data = base64.b64encode(img_file.read()).decode()
                    
                    os.unlink(tmp_file.name)
                    
                    return {
                        "success": True,
                        "base64_image": img_data,
                        "format": "png"
                    }
                else:
                    return {"error": f"grim failed: {result.stderr}"}
                    
        except Exception as e:
            return {"error": f"Wayland screenshot error: {str(e)}"}
    
    async def mouse_click(self, x: int, y: int, button: str = "left") -> Dict[str, Any]:
        """Perform mouse click at specified coordinates."""
        try:
            if self.display_server == 'wayland':
                return await self._mouse_click_wayland(x, y, button)
            else:
                return await self._mouse_click_x11(x, y, button)
        except Exception as e:
            return {"error": f"Mouse click failed: {str(e)}"}
    
    async def _mouse_click_x11(self, x: int, y: int, button: str) -> Dict[str, Any]:
        """Mouse click on X11 using xdotool."""
        try:
            # Use xdotool for X11 mouse control
            button_map = {"left": "1", "middle": "2", "right": "3"}
            btn = button_map.get(button, "1")
            
            result = subprocess.run([
                'xdotool', 'mousemove', str(x), str(y), 'click', btn
            ], capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "action": f"Clicked {button} button at ({x}, {y})"
                }
            else:
                return {"error": f"xdotool failed: {result.stderr}"}
                
        except Exception as e:
            return {"error": f"X11 mouse click error: {str(e)}"}
    
    async def _mouse_click_wayland(self, x: int, y: int, button: str) -> Dict[str, Any]:
        """Mouse click on Wayland using ydotool."""
        try:
            # Use ydotool for Wayland mouse control
            result = subprocess.run([
                'ydotool', 'mousemove', str(x), str(y)
            ], capture_output=True, text=True, timeout=5)
            
            if result.returncode != 0:
                return {"error": f"ydotool mousemove failed: {result.stderr}"}
            
            # Perform click
            button_map = {"left": "0x40", "middle": "0x41", "right": "0x42"}
            btn_code = button_map.get(button, "0x40")
            
            result = subprocess.run([
                'ydotool', 'click', btn_code
            ], capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "action": f"Clicked {button} button at ({x}, {y})"
                }
            else:
                return {"error": f"ydotool click failed: {result.stderr}"}
                
        except Exception as e:
            return {"error": f"Wayland mouse click error: {str(e)}"}
```

### 5.5.2. Container Configuration for GUI Access

To facilitate this direct access, the Qilbee OS Docker container and its corresponding Kubernetes Deployment must be configured to share the host's display server. This is achieved by:

#### For X11 Systems:
```yaml
# Kubernetes Deployment configuration
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qilbee-os
spec:
  template:
    spec:
      containers:
      - name: qilbee-os
        image: qilbee-os:latest
        env:
        - name: DISPLAY
          value: ":0"
        volumeMounts:
        - name: x11-socket
          mountPath: /tmp/.X11-unix
          readOnly: false
        - name: x11-auth
          mountPath: /root/.Xauthority
          readOnly: true
      volumes:
      - name: x11-socket
        hostPath:
          path: /tmp/.X11-unix
          type: Directory
      - name: x11-auth
        hostPath:
          path: /home/user/.Xauthority
          type: File
```

#### For Wayland Systems:
```yaml
# Kubernetes Deployment configuration for Wayland
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qilbee-os
spec:
  template:
    spec:
      containers:
      - name: qilbee-os
        image: qilbee-os:latest
        env:
        - name: WAYLAND_DISPLAY
          value: "wayland-0"
        - name: XDG_RUNTIME_DIR
          value: "/run/user/1000"
        volumeMounts:
        - name: wayland-socket
          mountPath: /run/user/1000
          readOnly: false
      volumes:
      - name: wayland-socket
        hostPath:
          path: /run/user/1000
          type: Directory
```

### 5.5.3. Security Implications

This direct access model carries inherent security risks. By sharing the host's display server socket, the Qilbee OS container and any process running within it gain significant privileges over the host's graphical session. A compromised Qilbee OS instance could potentially:

- **Keylogging**: Log all keystrokes entered into any application on the host desktop
- **Screen Recording**: Take screenshots of any window or the entire desktop
- **Input Injection**: Inject arbitrary mouse and keyboard events into other applications
- **Data Exfiltration**: Read content from any visible application window

### Security Mitigation Strategies

#### 1. Restricted Execution Context
- GUI automation tools should be limited to trusted environments only
- All GUI automation actions must be subject to rigorous RBAC policies (Section 6.4)
- Consider implementing a "approval required" mode for sensitive GUI operations

#### 2. Audit Logging  
```python
import logging
from datetime import datetime

class GUIActionAuditor:
    def __init__(self):
        self.audit_logger = logging.getLogger('qilbee.gui.audit')
        
    def log_gui_action(self, action_type: str, details: Dict[str, Any], user_id: str = None):
        """Log all GUI automation actions for security audit."""
        audit_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "action_type": action_type,
            "details": details,
            "user_id": user_id,
            "session_id": details.get("session_id"),
            "source_ip": details.get("source_ip")
        }
        
        self.audit_logger.info(f"GUI_ACTION: {json.dumps(audit_entry)}")
```

#### 3. Permission-Based Controls
```python
class GUIPermissionManager:
    def __init__(self, rbac_system):
        self.rbac = rbac_system
        
    def check_gui_permission(self, user_id: str, action: str) -> bool:
        """Check if user has permission for GUI action."""
        required_permissions = {
            "screenshot": "gui.screenshot.capture",
            "mouse_click": "gui.mouse.click", 
            "keyboard_input": "gui.keyboard.type",
            "window_control": "gui.window.control"
        }
        
        required_perm = required_permissions.get(action)
        if not required_perm:
            return False
            
        return self.rbac.user_has_permission(user_id, required_perm)
```

This architecture prioritizes functionality and direct control over strict isolation for GUI tasks. All non-GUI tools will continue to be executed within the highly restrictive nsjail sandbox to maintain the principle of least privilege wherever possible. The use of GUI automation tools should be limited to trusted environments, and all actions performed by these tools must be subject to the rigorous RBAC policies defined in Section 6.4.