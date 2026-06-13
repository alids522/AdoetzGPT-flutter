# Session Title Generation — Logic, Flow & System Prompt

---

## 1. THE SYSTEM PROMPT

### 1.1 The Default Prompt Template

This is the prompt that gets sent to the LLM to generate a chat title:

```
### Task:
Generate a concise, 3-5 word title with an emoji summarizing the chat history.
### Guidelines:
- The title should clearly represent the main theme or subject of the conversation.
- Use emojis that enhance understanding of the topic, but avoid quotation marks or special formatting.
- Write the title in the chat's primary language; default to English if multilingual.
- Prioritize accuracy over excessive creativity; keep it clear and simple.
- Your entire response must consist solely of the JSON object, without any introductory or concluding text.
- The output must be a single, raw JSON object, without any markdown code fences or other encapsulating text.
- Ensure no conversational text, affirmations, or explanations precede or follow the raw JSON output, as this will cause direct parsing failure.
### Output:
JSON format: { "title": "your concise title here" }
### Examples:
- { "title": "📉 Stock Market Trends" },
- { "title": "🍪 Perfect Chocolate Chip Recipe" },
- { "title": "Evolution of Music Streaming" },
- { "title": "Remote Work Productivity Tips" },
- { "title": "Artificial Intelligence in Healthcare" },
- { "title": "🎮 Video Game Development Insights" }
### Chat History:
<chat_history>
User: How do I bake a chocolate chip cookie from scratch?
Assistant: To bake chocolate chip cookies from scratch, you'll need flour, butter, sugar, eggs, vanilla extract, baking soda, salt, and chocolate chips...
</chat_history>
```

### 1.2 How the Prompt Is Sent to the LLM

The prompt is sent as a **single `user` message** — NOT as a `system` message:

```json
{
    "model": "gpt-4o-mini",
    "messages": [
        {
            "role": "user",
            "content": "### Task:\nGenerate a concise, 3-5 word title with an emoji...\n### Chat History:\n<chat_history>\nUser: ...\nAssistant: ...\n</chat_history>"
        }
    ],
    "stream": false
}
```

There is no `system` message. Just one `user` message containing the entire prompt template with the chat history injected.

### 1.3 What Chat History Is Included

Only the **last 2 messages** are included — the user's first question and the assistant's first answer. This keeps the prompt short and cheap.

### 1.4 Expected LLM Response

The LLM must return ONLY raw JSON:

```json
{ "title": "🍪 Perfect Chocolate Chip Cookies" }
```

No markdown fences, no explanatory text — just the JSON object.

### 1.5 Prompt Template Variables

The prompt supports these placeholder variables that get replaced before sending to the LLM:

#### Message Variables

| Variable | What Gets Injected |
|----------|-------------------|
| `{{MESSAGES}}` | All messages in the conversation |
| `{{MESSAGES:START:2}}` | First 2 messages |
| `{{MESSAGES:END:2}}` | Last 2 messages (the default) |
| `{{MESSAGES:MIDDLETRUNCATE:4}}` | First 2 + last 2 (for long chats) |
| Append `\|middletruncate:500` | Truncates each message to 500 chars |

#### User's Last Message Variables

| Variable | What Gets Injected |
|----------|-------------------|
| `{{prompt}}` | Full last user message |
| `{{prompt:start:100}}` | First 100 chars of last user message |
| `{{prompt:end:100}}` | Last 100 chars of last user message |
| `{{prompt:middletruncate:200}}` | Middle-truncated (start...end) |

#### User/Date Variables

| Variable | What Gets Injected |
|----------|-------------------|
| `{{USER_NAME}}` | Current user's display name |
| `{{CURRENT_DATE}}` | Today's date |
| `{{CURRENT_TIME}}` | Current time |
| `{{CURRENT_DATETIME}}` | Date + time combined |
| `{{USER_BIO}}` | User's profile bio |
| `{{USER_LOCATION}}` | User's location |

---

## 2. THE COMPLETE FLOW

### Visual Flow

```
User sends first message
        │
        ▼
Frontend includes flag: { title_generation: true }
in the chat completion request (only for new chats)
        │
        ▼
Backend receives request, processes the chat normally
(streaming the LLM response back to the user)
        │
        ▼
After LLM response completes → background task kicks in
        │
        ▼
Backend retrieves messages from DB, cleans them
(strips HTML tags, images, extra formatting)
        │
        ▼
Backend checks: is title_generation enabled?
        │
        ├─ YES → Continue to step below
        └─ NO  → Use first user message as title (skip LLM call)
        │
        ▼
Backend resolves which model to use for title generation
(may use a cheaper/different model than the main chat)
        │
        ▼
Backend builds the prompt:
  1. Select prompt template (custom or default)
  2. Replace {{MESSAGES:END:2}} with last 2 messages
  3. Replace {{prompt}} with last user message
  4. Replace {{USER_NAME}}, {{CURRENT_DATE}}, etc.
        │
        ▼
Backend calls LLM with stream=false, single user message
        │
        ▼
Backend parses LLM response:
  1. Extract text from response.choices[0].message.content
  2. Find first { and last } to extract JSON
  3. Parse JSON: { "title": "..." }
  4. Extract the "title" value
        │
        ▼
Backend saves title to database
        │
        ▼
Backend sends WebSocket event: { type: "chat:title", data: title }
        │
        ▼
Frontend receives WebSocket event
  → Updates the chat title in the UI
  → Refreshes the sidebar chat list
```

### Step-by-Step Breakdown

#### Step 1: Frontend Triggers Title Generation

When the user sends the **very first message** in a **new chat**, the frontend includes a `background_tasks` flag in the chat completion request:

```typescript
{
    messages: [...],
    model: "gpt-4o",
    background_tasks: {
        title_generation: true    // Only sent for the first message in a new chat
    }
}
```

**Conditions for triggering title generation:**
- It IS the first message in the conversation (no existing chat ID)
- The chat is NOT a temporary/guest chat
- The user has NOT disabled auto title generation in settings
- It is NOT a follow-up or regenerated message

#### Step 2: Backend Extracts the Flag

The backend pops the `background_tasks` from the request payload before processing the chat. The main chat LLM call happens normally (streaming response to the user). The title generation happens **after** the response completes.

#### Step 3: Background Task Handler Runs

After the full LLM response has been streamed to the user:

1. **Retrieve messages from database** — get all messages for this chat
2. **Clean the messages** — strip `<details>` HTML tags, remove image markdown `![](url)`, extract plain text from multi-part messages

#### Step 4: Check Configuration

The backend checks:
- Is `title_generation` set to `true` in the tasks dict?
- Is this a real saved chat (not a local/temporary chat)?

If `title_generation` is `false` or disabled globally, the LLM call is skipped entirely.

#### Step 5: Resolve the Task Model

The backend decides which model to use for title generation:

```
Is the main chat model a LOCAL connection (e.g. Ollama)?
  → Use TASK_MODEL if configured (e.g. "llama3.2")
  → Otherwise use the same model as the chat

Is the main chat model an EXTERNAL connection (e.g. OpenAI API)?
  → Use TASK_MODEL_EXTERNAL if configured (e.g. "gpt-4o-mini")
  → Otherwise use the same model as the chat
```

This allows using a cheaper/faster model for title generation while the user chats with a more powerful model.

#### Step 6: Build the Prompt

The template builder does 3 things in order:

1. **Replace `{{prompt}}` variables** — injects the last user message (with support for truncation)
2. **Replace `{{MESSAGES}}` variables** — injects formatted chat messages (default: last 2)
3. **Replace user/date variables** — injects `{{USER_NAME}}`, `{{CURRENT_DATE}}`, etc.

After all replacements, the prompt is a complete string ready to send as a `user` message.

#### Step 7: Call the LLM

```python
payload = {
    "model": task_model_id,          # The resolved task model
    "messages": [
        {
            "role": "user",
            "content": built_prompt   # The fully resolved prompt
        }
    ],
    "stream": False                   # NON-streaming — need full response
}
```

#### Step 8: Parse the Response

The LLM returns a standard OpenAI-compatible response. The backend extracts the title through robust parsing:

```python
# Get the raw text from the LLM response
title_string = response.choices[0].message.content

# Extract JSON by finding boundaries
title_string = title_string[title_string.find('{') : title_string.rfind('}') + 1]

# Parse the JSON
title = json.loads(title_string).get('title', fallback)
```

**Why `find('{')` and `rfind('}')`?** LLMs often add conversational text like "Here is the title:" before the JSON. This approach extracts just the JSON portion regardless of surrounding text.

#### Step 9: Save and Notify

1. **Save to database** — update the chat's title column
2. **Send WebSocket event** to the frontend:
   ```json
   { "type": "chat:title", "data": "🍪 Perfect Chocolate Chip Cookies" }
   ```

#### Step 10: Frontend Updates UI

The frontend receives the WebSocket event:
- Updates the chat title display
- Refreshes the sidebar chat list

---

## 3. THE FALLBACK CHAIN

Title generation has multiple fallback levels to ensure a title is ALWAYS shown:

```
Priority 1: LLM generates valid JSON with "title" key
    → Use this title
    │
    ▼ (if JSON parsing fails)
Priority 2: JSON parse failed, title = empty string
    → Use first user message content as title
    │
    ▼ (if LLM call never happened — disabled/skipped)
Priority 3: Title is still None, only 2 messages exist (first exchange)
    → Use first user message content as title (no LLM call)
    │
    ▼ (initial state, before any generation)
Priority 4: "New Chat"
    → This is the default until a real title is generated
    │
    ▼ (frontend-side fallback, for manual generation flows)
Priority 5: First 50 characters of first user message + "..."
    → Used when frontend-side title generation fails
```

---

## 4. MESSAGE CLEANING (Before Sending to LLM)

Before the messages are included in the title prompt, they are cleaned:

1. **Multi-part content extraction** — if a message has content as a list of parts (text, images, files), only the text part is extracted
2. **Strip `<details>` tags** — collapsible sections are removed via regex
3. **Strip image markdown** — `![alt](url)` patterns are removed
4. **Strip null bytes** — null bytes in titles are cleaned before saving

This ensures the LLM only sees clean, relevant text when generating the title.

---

## 5. HOW TO IMPLEMENT THIS IN YOUR OWN APP

### Minimal Backend Implementation (Python)

```python
import json
import asyncio
import time

TITLE_PROMPT = """### Task:
Generate a concise, 3-5 word title with an emoji summarizing the chat history.
### Guidelines:
- The title should clearly represent the main theme or subject of the conversation.
- Use emojis that enhance understanding of the topic, but avoid quotation marks or special formatting.
- Write the title in the chat's primary language; default to English if multilingual.
- Prioritize accuracy over excessive creativity; keep it clear and simple.
- Your entire response must consist solely of the JSON object, without any introductory or concluding text.
- The output must be a single, raw JSON object, without any markdown code fences or other encapsulating text.
### Output:
JSON format: { "title": "your concise title here" }
### Examples:
- { "title": "📉 Stock Market Trends" },
- { "title": "🍪 Perfect Chocolate Chip Recipe" },
- { "title": "🎮 Video Game Development Insights" }
### Chat History:
<chat_history>
{chat_history}
</chat_history>"""


def parse_title_from_llm_response(content: str) -> str | None:
    try:
        sanitized = content.replace("\u2018", '"').replace("\u2019", '"').replace("`", '"')
        start = sanitized.find("{")
        end = sanitized.rfind("}") + 1
        if start == -1 or end == 0:
            return None
        parsed = json.loads(sanitized[start:end])
        return parsed.get("title")
    except (json.JSONDecodeError, KeyError):
        return None


async def generate_chat_title(
    messages: list[dict],
    model: str = "gpt-4o-mini",
    llm_client=None,
) -> str:
    # 1. Take last 2 messages only
    last_messages = messages[-2:]

    # 2. Format as text
    chat_history = "\n".join(
        f"{msg['role'].capitalize()}: {msg['content']}"
        for msg in last_messages
    )

    # 3. Build prompt
    prompt = TITLE_PROMPT.replace("{chat_history}", chat_history)

    # 4. Call LLM (non-streaming, single user message)
    response = await llm_client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        stream=False,
    )

    content = response.choices[0].message.content or ""

    # 5. Parse with fallback chain
    title = parse_title_from_llm_response(content)

    if not title:
        user_msgs = [m for m in messages if m["role"] == "user"]
        title = user_msgs[0]["content"][:100] if user_msgs else "New Chat"

    return title


async def handle_title_generation(chat_id: str, messages: list[dict], db, ws_broadcast):
    """Run as a background task AFTER the chat response completes."""
    title = await generate_chat_title(messages)

    # Save to database
    await db.execute(
        "UPDATE chats SET title = ?, updated_at = ? WHERE id = ?",
        (title, int(time.time()), chat_id),
    )

    # Notify frontend via WebSocket
    await ws_broadcast(chat_id, {"type": "chat:title", "data": title})
```

### API Endpoint (FastAPI)

```python
from fastapi import FastAPI
import asyncio

app = FastAPI()


@app.post("/api/chat")
async def chat(request: ChatRequest):
    # 1. Process the chat normally (stream to user)
    response = await get_llm_response(request.messages)

    # 2. Schedule title generation as background task (non-blocking)
    if request.generate_title:
        asyncio.create_task(
            handle_title_generation(
                chat_id=response.chat_id,
                messages=request.messages,
                db=db,
                ws_broadcast=broadcast,
            )
        )

    return response
```

### Frontend Integration (TypeScript)

```typescript
// Send the flag with the first message
async function sendMessage(messages: Message[]) {
    await fetch("/api/chat", {
        method: "POST",
        body: JSON.stringify({
            messages,
            generate_title: messages.length === 1, // Only on first message
        }),
    });
}

// Listen for the title update via WebSocket
socket.on("chat:title", (data: { title: string }) => {
    setChatTitle(data.title);
    refreshSidebar();
});
```

---

## 6. KEY DESIGN DECISIONS

| Decision | Why |
|----------|-----|
| Prompt sent as `user` message, not `system` | Works with all LLMs, including those that don't support system messages |
| Only last 2 messages in prompt | Keeps it short and cheap — enough context to determine the topic |
| `stream: false` | Need the complete response to parse JSON; streaming adds overhead for no benefit |
| Background task (runs after response) | Doesn't block or slow down the user's chat experience |
| Robust JSON parsing (`find('{')` / `rfind('}')`) | LLMs often wrap JSON in explanatory text — this handles it gracefully |
| Separate task model | Use a cheap model (gpt-4o-mini) for titles while user chats with a powerful model |
| Only on first message | Title is set once at the start; subsequent messages don't regenerate it |
| "New Chat" as default | Immediate UI feedback; real title arrives asynchronously via WebSocket |
| Smart quote sanitization | LLMs sometimes return smart quotes (`'` `'`) instead of straight quotes, breaking JSON parse |
| Message cleaning before prompt | Strips HTML tags, images, and formatting to keep the prompt focused on text |
| Multiple fallback levels | Ensures a title is always shown even if the LLM fails or is disabled |
| Dual-write title storage | Queryable column for fast sidebar listing + JSON blob for full chat restoration |
