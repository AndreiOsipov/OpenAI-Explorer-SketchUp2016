# SketchUp WSL Proxy Payload

This document describes the request and response contract used by the SketchUp 2016 extension when it talks to the local WSL proxy.

## Source of truth

- UI settings collection: [as_openaiexplorer2016/as_openaiexplorer2016_ui.html](as_openaiexplorer2016/as_openaiexplorer2016_ui.html#L169)
- Settings normalization: [as_openaiexplorer2016/as_openaiexplorer2016.rb](as_openaiexplorer2016/as_openaiexplorer2016.rb#L89)
- Proxy request builder: [as_openaiexplorer2016/as_openaiexplorer2016.rb](as_openaiexplorer2016/as_openaiexplorer2016.rb#L298)
- Response parsing: [as_openaiexplorer2016/as_openaiexplorer2016.rb](as_openaiexplorer2016/as_openaiexplorer2016.rb#L334)
- Prompt template seed: [as_openaiexplorer2016/system_msgs.json](as_openaiexplorer2016/system_msgs.json#L5)

## Important behavior

- The browser UI does not send the full proxy payload. It sends a prompt plus a small settings object.
- The Ruby layer merges those incoming settings with persisted defaults before it calls the proxy.
- The Ruby layer forces `useCase` to `execute_ruby` and forces `executeCode` to `true`.
- The proxy receives a fully composed `system_prompt`. It does not need to rebuild the prompt from `system_msgs.json`.
- The proxy receives a structured `scene` snapshot generated inside SketchUp at request time.
- The proxy receives `history` as an array of prior messages. Assistant entries contain Ruby code that was previously returned, not rendered HTML.
- The optional `screenshot` field is present only when `submitModelView` is enabled in the dialog.

## Current default values

- `aiModel`: `gpt-5.4-mini`
- `maxTokens`: `2048`
- `temperature`: `0.2`
- `numPrompts`: `3`
- `aiEndpoint`: `http://127.0.0.1:5000/sketchup`
- `reasoning_effort`: `medium`
- `submitModelView`: `false`
- `modelViewQuality`: `low`
- `showRawData`: `false`
- `useCase`: `execute_ruby`

## Browser-to-Ruby payload

This is the payload sent from the WebDialog to Ruby when the user clicks Submit. It is not the final proxy payload.

```json
{
  "prompt": "Create a 2m x 2m x 2m grouped cube at the origin.",
  "settings": {
    "aiEndpoint": "http://127.0.0.1:5000/sketchup",
    "aiModel": "gpt-5.4-mini",
    "apiKey": "",
    "executeCode": true,
    "submitModelView": false,
    "showRawData": false,
    "modelViewQuality": "low",
    "useCase": "execute_ruby"
  }
}
```

The Ruby layer then expands this into the full proxy request shown below.

## Final proxy request shape

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `mode` | string | yes | Always `sketchup_ruby` in the current build. |
| `model` | string | yes | Taken from `aiModel`. |
| `prompt` | string | yes | User prompt from the dialog. |
| `system_prompt` | string | yes | Already merged and hardened before the proxy sees it. |
| `scene` | object | yes | Current SketchUp snapshot. If snapshotting fails it may be `{ "error": "..." }`. |
| `history` | array | yes | Prior messages, capped by `num_prompts`. |
| `options.execute_code` | boolean | yes | Always `true` in the current build. |
| `options.max_tokens` | integer | yes | Converted from the stored string setting. |
| `options.temperature` | number | yes | Converted from the stored string setting. |
| `options.reasoning_effort` | string | yes | One of `low`, `medium`, `high`. |
| `options.num_prompts` | integer | yes | Number of prior history entries to send. |
| `options.return_format` | string | yes | Always `ruby_only`. |
| `options.safety_mode` | string | yes | Always `sketchup_only`. |
| `api_key` | string | no | Included only when non-empty. |
| `screenshot` | object | no | Included only when `submitModelView` is enabled. |

## Full proxy payload example without screenshot

```json
{
  "mode": "sketchup_ruby",
  "model": "gpt-5.4-mini",
  "prompt": "Create a 2m x 2m x 2m grouped cube at the origin.",
  "system_prompt": "Act as a SketchUp 2016 copilot. Return only executable Ruby code with no Markdown fences, no HTML, and no explanation. The code must run at top level inside SketchUp, must stay inside the active SketchUp model, and must never access files, directories, URLs, sockets, processes, environment variables, or external applications. Target SketchUp 2016 and Ruby 2.0. Return only executable Ruby code. Do not wrap the response in Markdown fences. Do not include HTML or natural-language explanation. Never access files, directories, sockets, URLs, environment variables, subprocesses, shell commands, or external applications. Limit all model changes to the active SketchUp model.",
  "scene": {
    "app": {
      "sketchup_version": "16.1.1450",
      "ruby_version": "2.0.0",
      "platform": "i386-mingw32"
    },
    "model": {
      "title": "Untitled",
      "path": "",
      "bounds": {
        "min": [0.0, 0.0, 0.0],
        "max": [0.0, 0.0, 0.0],
        "width": 0.0,
        "height": 0.0,
        "depth": 0.0
      },
      "active_path": [],
      "selection": {
        "count": 0,
        "items": []
      },
      "active_entities": {
        "count": 2,
        "scanned": 2,
        "truncated": false,
        "counts_by_type": {
          "ConstructionPoint": 1,
          "Edge": 1
        },
        "sample": [
          {
            "type": "ConstructionPoint",
            "name": "",
            "layer": "Layer0",
            "material": "",
            "bounds": {
              "min": [0.0, 0.0, 0.0],
              "max": [0.0, 0.0, 0.0],
              "width": 0.0,
              "height": 0.0,
              "depth": 0.0
            },
            "persistent_id": 101
          },
          {
            "type": "Edge",
            "name": "",
            "layer": "Layer0",
            "material": "",
            "bounds": {
              "min": [0.0, 0.0, 0.0],
              "max": [1000.0, 0.0, 0.0],
              "width": 1000.0,
              "height": 0.0,
              "depth": 0.0
            },
            "persistent_id": 102
          }
        ]
      },
      "layers_count": 1,
      "materials_count": 0,
      "pages_count": 1,
      "definitions_count": 14
    },
    "camera": {
      "eye": [1200.0, -1800.0, 1400.0],
      "target": [0.0, 0.0, 0.0],
      "up": [0.0, 0.0, 1.0],
      "fov": 35.0,
      "perspective": true
    }
  },
  "history": [
    {
      "role": "user",
      "content": "Create a guide line from the origin to x=1000 mm."
    },
    {
      "role": "assistant",
      "content": "model = Sketchup.active_model\nentities = model.active_entities\nstart_pt = Geom::Point3d.new(0, 0, 0)\nend_pt = Geom::Point3d.new(1000.mm, 0, 0)\nentities.add_cline(start_pt, end_pt)"
    }
  ],
  "options": {
    "execute_code": true,
    "max_tokens": 2048,
    "temperature": 0.2,
    "reasoning_effort": "medium",
    "num_prompts": 3,
    "return_format": "ruby_only",
    "safety_mode": "sketchup_only"
  },
  "api_key": "provider-key-if-needed"
}
```

## Full proxy payload example with screenshot

This is the same contract with the optional `screenshot` object included. The Base64 payload is shortened for readability.

```json
{
  "mode": "sketchup_ruby",
  "model": "gpt-5.4-mini",
  "prompt": "Look at the current view and add a grouped red cube centered on the selected face.",
  "system_prompt": "Act as a SketchUp 2016 copilot. Return only executable Ruby code with no Markdown fences, no HTML, and no explanation. The code must run at top level inside SketchUp, must stay inside the active SketchUp model, and must never access files, directories, URLs, sockets, processes, environment variables, or external applications. Target SketchUp 2016 and Ruby 2.0. Return only executable Ruby code. Do not wrap the response in Markdown fences. Do not include HTML or natural-language explanation. Never access files, directories, sockets, URLs, environment variables, subprocesses, shell commands, or external applications. Limit all model changes to the active SketchUp model.",
  "scene": {
    "app": {
      "sketchup_version": "16.1.1450",
      "ruby_version": "2.0.0",
      "platform": "i386-mingw32"
    },
    "model": {
      "title": "SampleModel",
      "path": "C:/models/sample.skp",
      "bounds": {
        "min": [0.0, 0.0, 0.0],
        "max": [4000.0, 3000.0, 2800.0],
        "width": 4000.0,
        "height": 3000.0,
        "depth": 2800.0
      },
      "active_path": [],
      "selection": {
        "count": 1,
        "items": [
          {
            "type": "Face",
            "name": "",
            "layer": "Layer0",
            "material": "Default",
            "bounds": {
              "min": [0.0, 0.0, 0.0],
              "max": [1000.0, 1000.0, 0.0],
              "width": 1000.0,
              "height": 1000.0,
              "depth": 0.0
            },
            "persistent_id": 204
          }
        ]
      },
      "active_entities": {
        "count": 12,
        "scanned": 12,
        "truncated": false,
        "counts_by_type": {
          "Face": 3,
          "Edge": 9
        },
        "sample": []
      },
      "layers_count": 1,
      "materials_count": 2,
      "pages_count": 3,
      "definitions_count": 16
    },
    "camera": {
      "eye": [2100.0, -2600.0, 1700.0],
      "target": [500.0, 500.0, 0.0],
      "up": [0.0, 0.0, 1.0],
      "fov": 35.0,
      "perspective": true
    }
  },
  "history": [],
  "options": {
    "execute_code": true,
    "max_tokens": 2048,
    "temperature": 0.2,
    "reasoning_effort": "medium",
    "num_prompts": 3,
    "return_format": "ruby_only",
    "safety_mode": "sketchup_only"
  },
  "api_key": "provider-key-if-needed",
  "screenshot": {
    "mime_type": "image/png",
    "detail": "low",
    "data": "iVBORw0KGgoAAAANSUhEUgAA...trimmed...",
    "source": "active_view"
  }
}
```

## Recommended upstream prompt assembly inside the WSL proxy

Recommended mapping when the proxy forwards this request to a model provider:

1. Use `system_prompt` as the system message.
2. Reuse `history` as prior chat messages without changing roles.
3. Build the final user message from the raw `prompt` plus the serialized `scene` JSON.
4. Attach `screenshot` as image input only when the field is present.
5. Ask the provider to return Ruby only.
6. Normalize the final proxy response back to the SketchUp plugin contract shown below.

One safe user-message pattern is:

```text
User request:
<payload.prompt>

Current SketchUp scene JSON:
<payload.scene as JSON>
```

## Preferred proxy success response

The SketchUp plugin accepts several response shapes, but the safest contract is to always return a top-level `ruby` field.

```json
{
  "ruby": "model = Sketchup.active_model\nentities = model.active_entities\npoints = []\npoints << Geom::Point3d.new(0, 0, 0)\npoints << Geom::Point3d.new(2000.mm, 0, 0)\npoints << Geom::Point3d.new(2000.mm, 2000.mm, 0)\npoints << Geom::Point3d.new(0, 2000.mm, 0)\ngroup = entities.add_group\nface = group.entities.add_face(points)\nface.pushpull(2000.mm)",
  "usage": {
    "prompt_tokens": 1820,
    "completion_tokens": 211,
    "total_tokens": 2031
  },
  "choices": [
    {
      "finish_reason": "stop"
    }
  ]
}
```

## Other success response shapes accepted by the plugin

The plugin will also extract code from these fields, in this order:

1. `ruby`
2. `code`
3. `content`
4. `response`
5. `choices[0].message.content`

Returning `ruby` is still recommended because it removes ambiguity.

## Preferred proxy error response

Return an HTTP status code of 400 or higher and include a readable message in one of these forms.

```json
{
  "error": {
    "message": "The upstream model did not return Ruby-only output."
  }
}
```

```json
{
  "message": "Proxy could not reach the upstream model endpoint."
}
```

## Notes for the WSL proxy implementation

- The extension expects Ruby-only output, not Markdown.
- The extension already strips code fences if they appear, but the proxy should avoid producing them in the first place.
- The extension executes the returned Ruby immediately after a successful response.
- If the proxy wants to post-process provider output, it should do that before returning JSON to SketchUp.
- If token pressure becomes a problem, do any scene compression inside the proxy, not inside the SketchUp extension.