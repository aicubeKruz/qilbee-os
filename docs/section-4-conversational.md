# Section 4: Conversational Core and Python Tool Execution Engine

This section specifies the core functionalities that define Qilbee OS as a "conversational" system. It details the mechanisms for interpreting natural language, the architecture for a dynamic and extensible tool ecosystem, and the management of conversational state.

## 4.1. The Conversational Loop: From Natural Language to Actionable Tasks

The heart of Qilbee OS's conversational ability is a continuous processing loop managed by the Agent Orchestrator. This loop leverages Anthropic's Claude Sonnet 4 as its primary reasoning engine. The interaction will be conducted via a standardized API, specifically modeling the flow and data structures of Anthropic's Messages API, which provides robust support for multi-turn conversations and tool use.

### Conversational Flow Stages

The conversational loop proceeds through the following distinct stages:

#### 1. Input Reception
The user provides a prompt in natural language through the TUI. This may include image data, such as a screenshot.

#### 2. Contextualization and LLM Invocation
The Agent Orchestrator receives the prompt. It retrieves the existing conversational history for the session and combines it with the new prompt. It also retrieves the schemas of all currently available tools (see Section 4.2). This entire package—history, prompt, and tool definitions—is sent to the Claude Sonnet 4 model in a single API request.

#### 3. Response Parsing and Decision Making
The Orchestrator receives the LLM's response. It parses this response to determine the next action:
- If the response contains a standard text block, the content is relayed directly to the user via the TUI.
- If the response contains one or more `tool_use` content blocks, it signifies that the LLM has determined an action needs to be taken. The Orchestrator extracts the tool name and the structured input arguments from each block.

#### 4. Tool Execution Delegation
The Orchestrator passes the extracted tool name and arguments to the Python Tool Execution Engine and awaits the result.

#### 5. Result Synthesis and Continuation
The Execution Engine runs the tool and returns its output. The Orchestrator formats this output into a `tool_result` content block and sends it back to the LLM in a new API call, along with the full preceding context. This step "informs" the LLM of the outcome of its requested action.

#### 6. Final Response Generation
The LLM processes the tool result and generates a final, synthesized natural language response for the user, which is then displayed in the TUI. The loop then returns to stage 1, awaiting the next user input.

### Implementation Example

```python
import asyncio
from anthropic import Anthropic
from typing import List, Dict, Any

class ConversationalCore:
    def __init__(self, api_key: str):
        self.client = Anthropic(api_key=api_key)
        self.conversation_history: List[Dict] = []
        self.available_tools = self._load_available_tools()
    
    async def process_user_input(self, user_input: str, image_data: bytes = None) -> str:
        """Main conversational loop implementation."""
        
        # Stage 1: Input Reception
        message = {"role": "user", "content": user_input}
        if image_data:
            message["content"] = [
                {"type": "text", "text": user_input},
                {"type": "image", "source": {"type": "base64", "data": image_data}}
            ]
        
        self.conversation_history.append(message)
        
        # Stage 2: LLM Invocation with Context
        response = await self._call_claude_with_tools(
            messages=self.conversation_history,
            tools=self.available_tools
        )
        
        # Stage 3: Response Processing
        if self._has_tool_use(response):
            # Stage 4 & 5: Tool Execution and Result Processing
            tool_results = await self._execute_tools(response.content)
            
            # Add tool results to history
            self.conversation_history.append({
                "role": "assistant", 
                "content": response.content
            })
            self.conversation_history.append({
                "role": "user",
                "content": tool_results
            })
            
            # Stage 6: Final Response Generation
            final_response = await self._call_claude_with_tools(
                messages=self.conversation_history,
                tools=self.available_tools
            )
            
            self.conversation_history.append({
                "role": "assistant",
                "content": final_response.content
            })
            
            return final_response.content[0].text
        else:
            # Direct text response
            self.conversation_history.append({
                "role": "assistant",
                "content": response.content
            })
            return response.content[0].text
```

## 4.2. Tool Definition and Schema

In the Qilbee OS ecosystem, a "Tool" is formally defined as a Python function or a method of a class that can be executed to perform a specific, discrete action, such as querying a database, calling an external API, or performing a file system operation.

For a tool to be discoverable and usable by the LLM-driven conversational core, it must be accompanied by a structured definition. This definition will take the form of a JSON Schema object, precisely mirroring the `input_schema` format required by Anthropic's tool-use API. This schema serves as the "API documentation" for the tool that the LLM can understand.

### Tool Schema Structure

Each tool must contain:

- **name**: A unique, descriptive name for the tool.
- **description**: A clear, natural language description of what the tool does, what it is for, and when it should be used. This is the most critical field for the LLM's decision-making process.
- **input_schema**: A JSON Schema object that rigorously defines the parameters the tool accepts, including their names, data types (string, integer, boolean, etc.), whether they are required, and descriptions.

### Example Tool Definition

```python
def analyze_csv_data(file_path: str, analysis_type: str = "summary") -> dict:
    """Analyze CSV data and return statistical insights."""
    # Tool implementation
    pass

# Tool schema for Claude
ANALYZE_CSV_TOOL = {
    "name": "analyze_csv_data",
    "description": "Analyze CSV data files to extract statistical insights, trends, and summaries. Use this when users want to understand patterns in their data or get statistical analysis of CSV files.",
    "input_schema": {
        "type": "object",
        "properties": {
            "file_path": {
                "type": "string",
                "description": "Path to the CSV file to analyze"
            },
            "analysis_type": {
                "type": "string",
                "enum": ["summary", "trend", "correlation", "distribution"],
                "description": "Type of analysis to perform on the data",
                "default": "summary"
            }
        },
        "required": ["file_path"]
    }
}
```

## 4.2.1. Anthropic-Defined Tools: Computer, Text Editor, and Bash

In addition to user-defined tools, Qilbee OS will natively support Anthropic's predefined "computer use" tools, which are specifically designed to allow an agent to interact with a graphical user interface and the underlying shell. These tools are client-side implementations, meaning Qilbee OS is responsible for executing the actions they represent.

To enable these tools, all API requests to the Claude Sonnet 4 model MUST include the beta header: `"computer-use-2025-01-24"`.

### The Three Primary Anthropic-Defined Tools

#### Computer Tool (computer_20250124)
Enables direct interaction with the graphical user interface. Its actions include:
- **screenshot**: Captures the current display. The resulting image is returned to the model for visual analysis.
- **mouse_move**: Moves the cursor to specified screen coordinates.
- **left_click**: Simulates a left mouse click at specified coordinates.
- **type**: Simulates typing a string of text.
- **key**: Simulates pressing a single key or a key combination (e.g., ctrl+s).

#### Text Editor Tool (text_editor_20250728)
Provides functionality for viewing and editing text files. Its commands include:
- **view**: Reads the contents of a file or lists the contents of a directory.
- **create**: Creates a new, empty file.
- **str_replace**: Replaces a specific string within a file.  
- **insert**: Inserts a block of text at a specific line number in a file.
- Note: The `undo_edit` command is not supported in the version of the tool used by Claude 4 models.

#### Bash Tool
Allows for the direct execution of shell commands within the operating system.

### Implementation Example

```python
import subprocess
import base64
from PIL import ImageGrab
import pyautogui

class AnthropicToolsImplementation:
    
    async def execute_computer_action(self, action: str, **kwargs) -> dict:
        """Execute computer use tool actions."""
        
        if action == "screenshot":
            return await self._take_screenshot()
        elif action == "left_click":
            return await self._left_click(kwargs.get("coordinate", [0, 0]))
        elif action == "type":
            return await self._type_text(kwargs.get("text", ""))
        elif action == "key":
            return await self._press_key(kwargs.get("key", ""))
        else:
            raise ValueError(f"Unsupported computer action: {action}")
    
    async def _take_screenshot(self) -> dict:
        """Capture screenshot and return base64 encoded image."""
        try:
            screenshot = ImageGrab.grab()
            screenshot.save("/tmp/screenshot.png")
            
            with open("/tmp/screenshot.png", "rb") as img_file:
                img_data = base64.b64encode(img_file.read()).decode()
            
            return {
                "output": "Screenshot captured successfully",
                "base64_image": img_data
            }
        except Exception as e:
            return {"error": f"Failed to take screenshot: {str(e)}"}
    
    async def _left_click(self, coordinate: list) -> dict:
        """Simulate left mouse click."""
        try:
            x, y = coordinate
            pyautogui.click(x, y)
            return {"output": f"Clicked at coordinates ({x}, {y})"}
        except Exception as e:
            return {"error": f"Failed to click: {str(e)}"}
    
    async def execute_bash_command(self, command: str) -> dict:
        """Execute bash command securely."""
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=30  # 30 second timeout
            )
            
            return {
                "output": result.stdout,
                "error": result.stderr,
                "exit_code": result.returncode
            }
        except subprocess.TimeoutExpired:
            return {"error": "Command timed out after 30 seconds"}
        except Exception as e:
            return {"error": f"Command execution failed: {str(e)}"}
```

## 4.2.2. Qube API Integration

Qilbee OS will feature a native tool for integrating with the Qube Synthetic Workforce Technology platform. This tool allows the Agent Orchestrator to delegate high-level, complex, and multi-application business workflows to a specialized Qube agent, which operates through graphical user interfaces without requiring direct API integrations.

This integration provides a powerful abstraction layer. Instead of programming a sequence of low-level GUI interactions (mouse clicks, keyboard inputs), the Qilbee Orchestrator can delegate an entire business process to the Qube agent with a single tool call.

### Qube Tool Implementation

```python
import aiohttp
import json
from typing import Dict, Any

class QubeAPITool:
    def __init__(self, api_key: str, base_url: str = "https://api.qube.aicube.ca/"):
        self.api_key = api_key
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
    
    async def execute_task(self, task_description: str) -> Dict[str, Any]:
        """Execute a high-level business task via Qube API."""
        
        payload = {
            "task_description": task_description,
            "execution_mode": "autonomous",
            "timeout_minutes": 30
        }
        
        async with aiohttp.ClientSession() as session:
            try:
                # Submit task to Qube
                async with session.post(
                    f"{self.base_url}/tasks", 
                    headers=self.headers,
                    json=payload
                ) as response:
                    if response.status == 201:
                        task_data = await response.json()
                        task_id = task_data["task_id"]
                        
                        # Poll for completion
                        return await self._poll_task_completion(session, task_id)
                    else:
                        error_text = await response.text()
                        return {
                            "error": f"Failed to submit task: {response.status} - {error_text}"
                        }
            
            except Exception as e:
                return {"error": f"Qube API error: {str(e)}"}
    
    async def _poll_task_completion(self, session: aiohttp.ClientSession, task_id: str) -> Dict[str, Any]:
        """Poll Qube API for task completion."""
        import asyncio
        
        max_attempts = 60  # 30 minutes with 30-second intervals
        attempt = 0
        
        while attempt < max_attempts:
            try:
                async with session.get(
                    f"{self.base_url}/tasks/{task_id}",
                    headers=self.headers
                ) as response:
                    if response.status == 200:
                        task_status = await response.json()
                        
                        if task_status["status"] in ["completed", "failed"]:
                            return task_status
                        
                        # Task still running, wait and retry
                        await asyncio.sleep(30)
                        attempt += 1
                    else:
                        return {"error": f"Failed to get task status: {response.status}"}
            
            except Exception as e:
                return {"error": f"Error polling task status: {str(e)}"}
        
        return {"error": "Task timed out after 30 minutes"}

# Tool schema for Claude
QUBE_TASK_TOOL = {
    "name": "qube_task_executor",
    "description": "A specialized tool for executing complex, multi-step business processes across one or more desktop or web applications. Use this for high-level tasks like 'process all new insurance claims from the portal and update the financial spreadsheet' or 'onboard a new employee in the HR system'. This tool autonomously handles all necessary UI interactions, including reading screens, clicking buttons, and typing text, to complete the objective.",
    "input_schema": {
        "type": "object",
        "properties": {
            "task_description": {
                "type": "string",
                "description": "A detailed, natural language description of the high-level business task to be completed."
            }
        },
        "required": ["task_description"]
    }
}
```

## 4.3. The Tool Plugin and Execution Architecture

To foster a rich and extensible ecosystem of capabilities, Qilbee OS will not have a static, hard-coded set of tools. Instead, it will implement a dynamic plugin architecture that allows new tools to be added to the system simply by installing them as standard Python packages.

### Plugin Discovery Mechanism

The discovery mechanism for these plugins will be Python's standard `entry_points` system. This is a feature of Python packaging that allows a package to advertise objects it provides for discovery and use by other applications. Any third-party developer wishing to create a tool for Qilbee OS will package their code and, in their `pyproject.toml` or `setup.py` file, register their tool-providing module under a specific, designated group name: `qilbee.tools`.

### Plugin Discovery Implementation

```python
import importlib.metadata
from typing import Dict, List, Any
import inspect

class ToolPluginManager:
    def __init__(self):
        self.discovered_tools: Dict[str, Any] = {}
        self.tool_schemas: List[Dict] = []
    
    def discover_tools(self) -> None:
        """Discover and load all available tool plugins."""
        
        # Find all entry points for qilbee.tools
        entry_points = importlib.metadata.entry_points()
        
        if hasattr(entry_points, 'select'):
            # Python 3.10+ style
            tool_eps = entry_points.select(group='qilbee.tools')
        else:
            # Python 3.9 style
            tool_eps = entry_points.get('qilbee.tools', [])
        
        for entry_point in tool_eps:
            try:
                # Load the tool module
                tool_module = entry_point.load()
                
                # Extract tool function and schema
                if hasattr(tool_module, 'get_tool_function'):
                    tool_func = tool_module.get_tool_function()
                    tool_schema = tool_module.get_tool_schema()
                    
                    self.discovered_tools[tool_schema['name']] = tool_func
                    self.tool_schemas.append(tool_schema)
                    
                    print(f"Loaded tool: {tool_schema['name']}")
                
            except Exception as e:
                print(f"Failed to load tool from {entry_point.name}: {e}")
    
    def get_tool_schemas(self) -> List[Dict]:
        """Return all tool schemas for LLM."""
        return self.tool_schemas
    
    async def execute_tool(self, tool_name: str, tool_args: Dict) -> Dict[str, Any]:
        """Execute a discovered tool."""
        if tool_name not in self.discovered_tools:
            return {"error": f"Tool '{tool_name}' not found"}
        
        try:
            tool_func = self.discovered_tools[tool_name]
            
            # Execute tool (handle both sync and async functions)
            if inspect.iscoroutinefunction(tool_func):
                result = await tool_func(**tool_args)
            else:
                result = tool_func(**tool_args)
            
            return {"result": result, "success": True}
            
        except Exception as e:
            return {"error": f"Tool execution failed: {str(e)}", "success": False}
```

### Example Plugin Package Structure

```python
# my_qilbee_tool/tool.py
def database_query(sql: str, database: str = "default") -> dict:
    """Execute SQL query against specified database."""
    # Implementation here
    return {"rows": [], "count": 0}

def get_tool_function():
    return database_query

def get_tool_schema():
    return {
        "name": "database_query",
        "description": "Execute SQL queries against databases to retrieve or manipulate data.",
        "input_schema": {
            "type": "object",
            "properties": {
                "sql": {
                    "type": "string",
                    "description": "SQL query to execute"
                },
                "database": {
                    "type": "string",
                    "description": "Database connection name",
                    "default": "default"
                }
            },
            "required": ["sql"]
        }
    }

# pyproject.toml
[project.entry-points."qilbee.tools"]
database_tool = "my_qilbee_tool.tool"
```

## 4.4. State and Context Management in Multi-Turn Conversations

The Agent Orchestrator bears the full responsibility for maintaining the state and context of each ongoing conversation. A conversation is defined as a sequence of interactions with a single user or client.

### Conversation State Structure

The state is primarily composed of the conversational history. This history is an ordered list of messages, meticulously structured according to the format required by the backing LLM API. Each turn in the conversation may consist of multiple messages:

1. A `user` role message containing the user's prompt.
2. An `assistant` role message containing the LLM's initial response, which may include a `tool_use` request.
3. A `user` role message containing a `tool_result` block, which is programmatically generated by the Orchestrator after the tool executes.
4. A final `assistant` role message containing the LLM's synthesized response to the user.

### Context Management Implementation

```python
from typing import List, Dict, Any
import json
from datetime import datetime

class ConversationManager:
    def __init__(self):
        self.active_sessions: Dict[str, List[Dict]] = {}
        self.session_metadata: Dict[str, Dict] = {}
    
    def create_session(self, session_id: str, user_id: str = None) -> None:
        """Create a new conversation session."""
        self.active_sessions[session_id] = []
        self.session_metadata[session_id] = {
            "user_id": user_id,
            "created_at": datetime.utcnow().isoformat(),
            "last_activity": datetime.utcnow().isoformat(),
            "message_count": 0
        }
    
    def add_message(self, session_id: str, role: str, content: Any) -> None:
        """Add a message to the conversation history."""
        if session_id not in self.active_sessions:
            self.create_session(session_id)
        
        message = {
            "role": role,
            "content": content,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        self.active_sessions[session_id].append(message)
        self.session_metadata[session_id]["last_activity"] = datetime.utcnow().isoformat()
        self.session_metadata[session_id]["message_count"] += 1
    
    def get_conversation_history(self, session_id: str) -> List[Dict]:
        """Get the complete conversation history for Claude API."""
        if session_id not in self.active_sessions:
            return []
        
        # Return messages in Claude API format (without timestamps)
        return [
            {"role": msg["role"], "content": msg["content"]}
            for msg in self.active_sessions[session_id]
        ]
    
    def get_session_summary(self, session_id: str) -> Dict[str, Any]:
        """Get session metadata and statistics."""
        if session_id not in self.active_sessions:
            return {"error": "Session not found"}
        
        return {
            "session_id": session_id,
            "metadata": self.session_metadata[session_id],
            "message_count": len(self.active_sessions[session_id]),
            "last_messages": self.active_sessions[session_id][-5:]  # Last 5 messages
        }
    
    def cleanup_old_sessions(self, max_age_hours: int = 24) -> int:
        """Remove sessions older than specified hours."""
        from datetime import datetime, timedelta
        
        cutoff_time = datetime.utcnow() - timedelta(hours=max_age_hours)
        sessions_to_remove = []
        
        for session_id, metadata in self.session_metadata.items():
            last_activity = datetime.fromisoformat(metadata["last_activity"])
            if last_activity < cutoff_time:
                sessions_to_remove.append(session_id)
        
        for session_id in sessions_to_remove:
            del self.active_sessions[session_id]
            del self.session_metadata[session_id]
        
        return len(sessions_to_remove)
```

This entire, unabridged history is passed to the LLM with every new request from the user. This ensures that the model has the complete context of the preceding interaction, allowing it to understand follow-up questions, refer to previous results, and maintain a coherent and logical dialogue over multiple turns. The Orchestrator will manage separate history objects for each concurrent user session.

The implementation ensures that conversational context is preserved across tool executions and provides the foundation for sophisticated, multi-turn interactions that can span complex, multi-step workflows.