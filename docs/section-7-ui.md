# Section 7: Operator and User Interface (TUI)

This section specifies the design and implementation of the primary interface for human operators to interact with, manage, and monitor a Qilbee OS instance. The interface will be a sophisticated, terminal-based application built using modern Python frameworks optimized for real-time, asynchronous operation.

## 7.1. Interface Framework: Building with the Textual Application Framework

The primary command-line interface for Qilbee OS will be a Textual-based Text User Interface (TUI) application.

The selection of the Textual framework is driven by its modern architecture and rich feature set, which are uniquely suited to the demands of a real-time, conversational operating system. Textual, which is built upon the powerful Rich rendering library, provides a complete application framework for building complex, interactive, and visually appealing TUIs using Python. Key advantages include its comprehensive library of pre-built widgets (inputs, buttons, scrollable views, etc.), a flexible CSS-like styling and layout system, and, most importantly, its native support for asynchronous programming. This async-first design is essential for building a responsive user interface that can handle real-time data streams and background processing without freezing or becoming unresponsive.

### Textual Framework Advantages

- **Modern Architecture**: Built on asyncio for true concurrent operation
- **Rich Rendering**: Advanced text formatting, syntax highlighting, and visual elements
- **Widget Library**: Comprehensive set of pre-built UI components
- **CSS-like Styling**: Flexible theming and layout system
- **Cross-platform**: Works on Linux, macOS, and Windows terminals
- **Responsive Design**: Adapts to different terminal sizes and capabilities

## 7.2. Core UI Components

The Qilbee OS TUI will be composed of several key components, arranged in a logical layout to provide a clear and efficient user experience.

### UI Component Architecture

```python
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical
from textual.widgets import (
    Header, Footer, Input, Log, DataTable, 
    Button, Static, ProgressBar, TabbedContent, TabPane
)
from textual.reactive import reactive
from textual.message import Message
from rich.console import RenderableType
from rich.text import Text
from rich.markdown import Markdown
from rich.syntax import Syntax
import asyncio
from typing import Dict, Any, Optional

class ConversationPane(Log):
    """Scrollable conversation display with rich content rendering."""
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.can_focus = False
        self.auto_scroll = True
    
    def add_user_message(self, message: str):
        """Add a user message to the conversation."""
        user_text = Text()
        user_text.append("🧑 User: ", style="bold blue")
        user_text.append(message, style="white")
        self.write(user_text)
    
    def add_agent_message(self, message: str):
        """Add an agent response to the conversation."""
        agent_text = Text()
        agent_text.append("🤖 Qilbee: ", style="bold green")
        
        # Render markdown if message contains markdown
        if any(marker in message for marker in ['**', '*', '`', '#']):
            markdown = Markdown(message)
            self.write(markdown)
        else:
            agent_text.append(message, style="white")
            self.write(agent_text)
    
    def add_tool_execution(self, tool_name: str, status: str, output: str = None):
        """Add tool execution information."""
        tool_text = Text()
        tool_text.append("🔧 Tool: ", style="bold yellow")
        tool_text.append(f"{tool_name} ", style="yellow")
        
        if status == "executing":
            tool_text.append("⏳ Executing...", style="yellow")
        elif status == "success":
            tool_text.append("✅ Success", style="green")
            if output:
                # Show code output with syntax highlighting
                if tool_name in ["bash", "python"]:
                    syntax = Syntax(output, tool_name, theme="monokai", line_numbers=False)
                    self.write(syntax)
                else:
                    self.write(Text(output, style="dim white"))
        elif status == "error":
            tool_text.append("❌ Failed", style="red")
            if output:
                self.write(Text(output, style="red"))
        
        self.write(tool_text)
    
    def add_system_message(self, message: str, level: str = "info"):
        """Add system status messages."""
        system_text = Text()
        
        if level == "info":
            system_text.append("ℹ️  System: ", style="bold cyan")
            system_text.append(message, style="cyan")
        elif level == "warning":
            system_text.append("⚠️  Warning: ", style="bold yellow")
            system_text.append(message, style="yellow")
        elif level == "error":
            system_text.append("❌ Error: ", style="bold red")
            system_text.append(message, style="red")
        
        self.write(system_text)

class StatusBar(Static):
    """Real-time status information display."""
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.agent_status = "disconnected"
        self.active_tasks = 0
        self.worker_count = 0
        self.last_update = None
    
    def update_status(self, 
                     agent_status: str = None,
                     active_tasks: int = None, 
                     worker_count: int = None):
        """Update status information."""
        if agent_status:
            self.agent_status = agent_status
        if active_tasks is not None:
            self.active_tasks = active_tasks
        if worker_count is not None:
            self.worker_count = worker_count
        
        self.last_update = "now"
        self._refresh_display()
    
    def _refresh_display(self):
        """Refresh the status display."""
        status_text = Text()
        
        # Agent status with color coding
        if self.agent_status == "active":
            status_text.append("● ACTIVE", style="bold green")
        elif self.agent_status == "suspended":
            status_text.append("⏸ SUSPENDED", style="bold yellow") 
        elif self.agent_status == "waiting":
            status_text.append("⏳ WAITING", style="bold blue")
        else:
            status_text.append("● OFFLINE", style="bold red")
        
        status_text.append(f" | Tasks: {self.active_tasks}", style="white")
        status_text.append(f" | Workers: {self.worker_count}", style="white")
        
        if self.last_update:
            status_text.append(f" | Updated: {self.last_update}", style="dim white")
        
        self.update(status_text)

class TaskDashboard(DataTable):
    """Task monitoring dashboard."""
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.cursor_type = "row"
        self.zebra_stripes = True
    
    async def on_mount(self):
        """Initialize the table structure."""
        self.add_columns("Task ID", "Status", "Tool", "Started", "Duration", "Progress")
        
        # Add sample data
        await self.populate_tasks()
    
    async def populate_tasks(self):
        """Populate with current task data."""
        # This would connect to the actual task monitoring system
        sample_tasks = [
            ("task_001", "Running", "data_analyzer", "10:30:15", "00:02:30", "75%"),
            ("task_002", "Pending", "file_processor", "10:32:00", "-", "0%"),
            ("task_003", "Completed", "report_gen", "10:25:00", "00:03:45", "100%"),
            ("task_004", "Failed", "network_scan", "10:28:30", "00:00:15", "Error"),
        ]
        
        for task in sample_tasks:
            await self.add_row(*task)
    
    async def refresh_tasks(self):
        """Refresh task data from the monitoring system."""
        # Clear existing data
        self.clear()
        
        # Repopulate with fresh data
        await self.populate_tasks()

class WorkerDashboard(DataTable):
    """Worker monitoring dashboard."""
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.cursor_type = "row"
        self.zebra_stripes = True
    
    async def on_mount(self):
        """Initialize worker monitoring table."""
        self.add_columns("Worker ID", "Status", "Current Task", "CPU %", "Memory %", "Uptime")
        
        await self.populate_workers()
    
    async def populate_workers(self):
        """Populate with current worker data."""
        sample_workers = [
            ("worker_001", "Active", "task_001", "45%", "30%", "2h 15m"),
            ("worker_002", "Idle", "-", "5%", "15%", "2h 15m"), 
            ("worker_003", "Active", "task_003", "78%", "55%", "1h 45m"),
        ]
        
        for worker in sample_workers:
            await self.add_row(*worker)

class CommandInput(Input):
    """Enhanced command input with history and autocomplete."""
    
    def __init__(self, **kwargs):
        super().__init__(placeholder="Enter your command or question...", **kwargs)
        self.command_history = []
        self.history_index = -1
    
    def add_to_history(self, command: str):
        """Add command to history."""
        if command and (not self.command_history or self.command_history[-1] != command):
            self.command_history.append(command)
            self.history_index = len(self.command_history)
    
    async def key_up(self):
        """Navigate command history up."""
        if self.command_history and self.history_index > 0:
            self.history_index -= 1
            self.value = self.command_history[self.history_index]
    
    async def key_down(self):
        """Navigate command history down.""" 
        if self.command_history and self.history_index < len(self.command_history) - 1:
            self.history_index += 1
            self.value = self.command_history[self.history_index]
        elif self.history_index == len(self.command_history) - 1:
            self.history_index = len(self.command_history)
            self.value = ""
```

### Main Application Layout

```python
class QilbeeOSTUI(App):
    """Main Qilbee OS Terminal User Interface."""
    
    CSS = """
    #conversation {
        height: 1fr;
        border: solid $primary;
        padding: 1;
    }
    
    #input-container {
        height: 3;
        background: $surface;
    }
    
    #status-bar {
        height: 1;
        background: $primary;
        color: $text;
        content-align: center middle;
    }
    
    #sidebar {
        width: 30%;
        background: $surface;
    }
    
    .dashboard-tab {
        height: 1fr;
    }
    """
    
    TITLE = "Qilbee OS - Conversational Operating System"
    SUB_TITLE = "Enterprise Agent Platform"
    
    def __init__(self, agent_orchestrator=None, **kwargs):
        super().__init__(**kwargs)
        self.agent_orchestrator = agent_orchestrator
        self.conversation_active = False
        
    def compose(self) -> ComposeResult:
        """Compose the UI layout."""
        yield Header()
        
        with Horizontal():
            # Main conversation area
            with Vertical():
                yield ConversationPane(id="conversation")
                
                with Container(id="input-container"):
                    yield CommandInput(id="command-input")
            
            # Sidebar with monitoring dashboards
            with Vertical(id="sidebar"):
                with TabbedContent():
                    with TabPane("Tasks", id="tasks-tab"):
                        yield TaskDashboard(id="task-dashboard", classes="dashboard-tab")
                    
                    with TabPane("Workers", id="workers-tab"):
                        yield WorkerDashboard(id="worker-dashboard", classes="dashboard-tab")
        
        yield StatusBar(id="status-bar")
        yield Footer()
    
    async def on_mount(self):
        """Initialize the application."""
        conversation = self.query_one("#conversation", ConversationPane)
        conversation.add_system_message("Qilbee OS initialized successfully", "info")
        conversation.add_system_message("Type your commands or questions below", "info")
        
        # Start background monitoring tasks
        self.set_interval(5.0, self.update_monitoring_data)
        
        # Focus on input
        self.query_one("#command-input", CommandInput).focus()
    
    async def on_input_submitted(self, event: Input.Submitted):
        """Handle user input submission."""
        if event.input.id == "command-input":
            command = event.value.strip()
            if not command:
                return
            
            # Add to conversation
            conversation = self.query_one("#conversation", ConversationPane)
            conversation.add_user_message(command)
            
            # Add to history
            command_input = self.query_one("#command-input", CommandInput)
            command_input.add_to_history(command)
            command_input.value = ""
            
            # Process command
            await self.process_user_command(command)
    
    async def process_user_command(self, command: str):
        """Process user command through the agent orchestrator."""
        conversation = self.query_one("#conversation", ConversationPane)
        
        try:
            if self.agent_orchestrator:
                # Show agent is thinking
                conversation.add_system_message("Processing...", "info")
                
                # Send to agent orchestrator
                response = await self.agent_orchestrator.process_user_input(command)
                
                # Display response
                conversation.add_agent_message(response)
                
            else:
                # Fallback for demo/testing
                conversation.add_agent_message(f"Echo: {command}")
                
        except Exception as e:
            conversation.add_system_message(f"Error processing command: {str(e)}", "error")
    
    async def update_monitoring_data(self):
        """Update monitoring dashboards with fresh data."""
        try:
            # Update status bar
            status_bar = self.query_one("#status-bar", StatusBar)
            status_bar.update_status(
                agent_status="active",
                active_tasks=3,
                worker_count=2
            )
            
            # Refresh task dashboard if visible
            if self.query("#task-dashboard"):
                task_dashboard = self.query_one("#task-dashboard", TaskDashboard)
                await task_dashboard.refresh_tasks()
                
        except Exception as e:
            # Log error but don't crash the UI
            pass
    
    def action_toggle_sidebar(self):
        """Toggle sidebar visibility."""
        sidebar = self.query_one("#sidebar")
        sidebar.display = not sidebar.display
    
    def action_clear_conversation(self):
        """Clear conversation history."""
        conversation = self.query_one("#conversation", ConversationPane)
        conversation.clear()
        conversation.add_system_message("Conversation cleared", "info")
    
    def action_quit(self):
        """Quit the application."""
        self.exit()

# Key bindings
QilbeeOSTUI.BINDINGS = [
    ("ctrl+c", "quit", "Quit"),
    ("ctrl+l", "clear_conversation", "Clear"),
    ("ctrl+s", "toggle_sidebar", "Toggle Sidebar"),
    ("f1", "help", "Help"),
]
```

## 7.3. Real-time Updates and Asynchronous Display Management

The TUI must be fully asynchronous to deliver a fluid and responsive user experience. It cannot block or wait while the Agent Orchestrator is processing a request or a long-running task is executing in the background.

### Asynchronous Architecture Implementation

```python
import asyncio
from typing import AsyncGenerator
from textual.widgets import LoadingIndicator

class AsyncConversationManager:
    """Manages asynchronous conversation flow with streaming support."""
    
    def __init__(self, tui_app: QilbeeOSTUI, agent_orchestrator):
        self.tui = tui_app
        self.orchestrator = agent_orchestrator
        self.active_streams = {}
    
    async def process_streaming_response(self, command: str, session_id: str):
        """Handle streaming responses from the agent."""
        conversation = self.tui.query_one("#conversation", ConversationPane)
        
        try:
            # Start streaming response
            response_stream = self.orchestrator.stream_response(command, session_id)
            
            current_response = ""
            async for chunk in response_stream:
                if chunk.get("type") == "text":
                    current_response += chunk.get("content", "")
                    # Update conversation with incremental content
                    conversation.add_agent_message(current_response)
                
                elif chunk.get("type") == "tool_use":
                    tool_name = chunk.get("name")
                    conversation.add_tool_execution(tool_name, "executing")
                    
                elif chunk.get("type") == "tool_result":
                    tool_name = chunk.get("tool_name")
                    success = chunk.get("success", False)
                    output = chunk.get("output", "")
                    
                    status = "success" if success else "error"
                    conversation.add_tool_execution(tool_name, status, output)
                
                # Small delay to prevent UI flooding
                await asyncio.sleep(0.1)
                
        except Exception as e:
            conversation.add_system_message(f"Streaming error: {str(e)}", "error")

class RealTimeMonitor:
    """Real-time system monitoring with event streaming."""
    
    def __init__(self, tui_app: QilbeeOSTUI):
        self.tui = tui_app
        self.monitoring_active = False
        self.event_queue = asyncio.Queue()
    
    async def start_monitoring(self):
        """Start real-time monitoring of system events."""
        self.monitoring_active = True
        
        # Start monitoring tasks
        monitor_tasks = [
            asyncio.create_task(self.monitor_task_queue()),
            asyncio.create_task(self.monitor_worker_status()),
            asyncio.create_task(self.monitor_system_resources()),
            asyncio.create_task(self.process_events())
        ]
        
        try:
            await asyncio.gather(*monitor_tasks)
        except asyncio.CancelledError:
            self.monitoring_active = False
    
    async def monitor_task_queue(self):
        """Monitor task queue for changes."""
        while self.monitoring_active:
            try:
                # Connect to Celery monitoring
                # This would integrate with actual Celery monitoring APIs
                task_stats = await self.get_task_statistics()
                
                await self.event_queue.put({
                    "type": "task_update",
                    "data": task_stats
                })
                
                await asyncio.sleep(2)  # Update every 2 seconds
                
            except Exception as e:
                await asyncio.sleep(5)  # Retry after error
    
    async def monitor_worker_status(self):
        """Monitor Celery worker status."""
        while self.monitoring_active:
            try:
                worker_stats = await self.get_worker_statistics()
                
                await self.event_queue.put({
                    "type": "worker_update", 
                    "data": worker_stats
                })
                
                await asyncio.sleep(3)  # Update every 3 seconds
                
            except Exception as e:
                await asyncio.sleep(5)
    
    async def monitor_system_resources(self):
        """Monitor system resource usage."""
        import psutil
        
        while self.monitoring_active:
            try:
                system_stats = {
                    "cpu_percent": psutil.cpu_percent(interval=1),
                    "memory_percent": psutil.virtual_memory().percent,
                    "disk_usage": psutil.disk_usage('/').percent
                }
                
                await self.event_queue.put({
                    "type": "system_update",
                    "data": system_stats
                })
                
                await asyncio.sleep(5)  # Update every 5 seconds
                
            except Exception as e:
                await asyncio.sleep(10)
    
    async def process_events(self):
        """Process monitoring events and update UI."""
        while self.monitoring_active:
            try:
                event = await asyncio.wait_for(self.event_queue.get(), timeout=1.0)
                
                if event["type"] == "task_update":
                    await self.update_task_dashboard(event["data"])
                elif event["type"] == "worker_update":
                    await self.update_worker_dashboard(event["data"])
                elif event["type"] == "system_update":
                    await self.update_status_bar(event["data"])
                    
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                # Log error but continue monitoring
                pass
    
    async def update_task_dashboard(self, task_data):
        """Update task dashboard with new data."""
        try:
            task_dashboard = self.tui.query_one("#task-dashboard", TaskDashboard)
            # Update dashboard data asynchronously
            await task_dashboard.refresh_tasks()
        except Exception:
            pass
    
    async def update_worker_dashboard(self, worker_data): 
        """Update worker dashboard with new data."""
        try:
            worker_dashboard = self.tui.query_one("#worker-dashboard", WorkerDashboard)
            # Update worker information
            # Implementation would refresh worker data
        except Exception:
            pass
    
    async def update_status_bar(self, system_data):
        """Update status bar with system information."""
        try:
            status_bar = self.tui.query_one("#status-bar", StatusBar)
            status_bar.update_status(
                agent_status="active",
                active_tasks=len(system_data.get("active_tasks", [])),
                worker_count=system_data.get("worker_count", 0)
            )
        except Exception:
            pass
    
    async def get_task_statistics(self):
        """Get current task statistics from Celery."""
        # This would integrate with actual Celery monitoring
        return {
            "active_tasks": [],
            "pending_tasks": [],
            "completed_tasks": [],
            "failed_tasks": []
        }
    
    async def get_worker_statistics(self):
        """Get current worker statistics from Celery."""
        # This would integrate with actual Celery worker monitoring
        return {
            "workers": [],
            "total_workers": 0,
            "active_workers": 0
        }
```

### Application Entry Point

```python
async def main():
    """Main application entry point."""
    
    # Initialize agent orchestrator (would be actual implementation)
    agent_orchestrator = None  # AgentOrchestrator()
    
    # Create and run TUI application
    app = QilbeeOSTUI(agent_orchestrator=agent_orchestrator)
    
    # Start real-time monitoring
    monitor = RealTimeMonitor(app)
    monitoring_task = asyncio.create_task(monitor.start_monitoring())
    
    try:
        await app.run_async()
    finally:
        monitoring_task.cancel()
        try:
            await monitoring_task
        except asyncio.CancelledError:
            pass

if __name__ == "__main__":
    asyncio.run(main())
```

## 7.4. Advanced UI Features

### 7.4.1. Keyboard Shortcuts and Navigation

The TUI supports comprehensive keyboard navigation:

- **Ctrl+C**: Quit application
- **Ctrl+L**: Clear conversation history  
- **Ctrl+S**: Toggle sidebar visibility
- **Tab**: Navigate between UI elements
- **Up/Down**: Navigate command history
- **F1**: Show help dialog
- **Ctrl+T**: Switch between dashboard tabs

### 7.4.2. Theme and Styling Support

```python
# Custom CSS themes
QILBEE_THEMES = {
    "default": {
        "primary": "#0078d4",
        "surface": "#1e1e1e", 
        "text": "#ffffff",
        "success": "#107c10",
        "warning": "#ff8c00",
        "error": "#d13438"
    },
    "light": {
        "primary": "#0078d4",
        "surface": "#f5f5f5",
        "text": "#000000", 
        "success": "#107c10",
        "warning": "#ff8c00",
        "error": "#d13438"
    }
}
```

### 7.4.3. Export and Logging

```python
class ConversationExporter:
    """Export conversation history in various formats."""
    
    @staticmethod
    def export_to_markdown(conversation_history: list) -> str:
        """Export conversation to markdown format."""
        markdown_content = "# Qilbee OS Conversation Log\n\n"
        
        for entry in conversation_history:
            if entry["role"] == "user":
                markdown_content += f"## User\n{entry['content']}\n\n"
            elif entry["role"] == "assistant":
                markdown_content += f"## Qilbee Agent\n{entry['content']}\n\n"
            elif entry["role"] == "tool":
                markdown_content += f"### Tool Execution: {entry['tool_name']}\n"
                markdown_content += f"```\n{entry['output']}\n```\n\n"
        
        return markdown_content
    
    @staticmethod
    def export_to_json(conversation_history: list) -> str:
        """Export conversation to JSON format."""
        import json
        return json.dumps(conversation_history, indent=2)
```

This comprehensive TUI implementation provides a modern, responsive interface that leverages Textual's async-first architecture to deliver real-time updates and smooth user interactions, making it suitable for managing complex distributed systems like Qilbee OS.