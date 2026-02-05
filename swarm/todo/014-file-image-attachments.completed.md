# Task: File and Image Attachments

## Completion Note (Agent b723b367)

This feature was verified as fully implemented by agent b723b367 on 2026-02-05. The implementation includes:

1. **Attachment schema** - `lib/elixirchat/chat/attachment.ex` with all required fields (filename, original_filename, content_type, size) and helper functions
2. **Migration** - `priv/repo/migrations/20260205053000_create_attachments.exs` (already applied)
3. **Message association** - `has_many :attachments` in Message schema
4. **Chat context** - `send_message/4` accepts `:attachments` option and creates attachment records
5. **Endpoint** - Serves `/uploads` from `priv/static/uploads`
6. **ChatLive** - Full UI implementation with:
   - File upload configuration (`allow_upload`)
   - Upload preview with live image preview
   - Upload cancellation
   - Image display inline in messages
   - Non-image file download links
   - Error handling for invalid file types and sizes

---

## Description
Add the ability to upload and share files and images in chat conversations. This is a fundamental feature in modern chat applications that allows users to share documents, photos, and other media. Images should display inline in the chat, while other file types show as downloadable attachments.

## Requirements
- Users can attach files when sending messages (button next to send)
- Support common image formats: jpg, png, gif, webp
- Support common document formats: pdf, txt, doc, docx
- Maximum file size: 10MB per file
- Images display as thumbnails inline in the chat
- Non-image files show as downloadable links with file name and size
- Files are stored locally in priv/static/uploads (for local dev)
- Real-time: attachments appear for all conversation members via PubSub
- Clicking an image opens it in full size (modal or new tab)
- File attachments persist across page refreshes

## Implementation Steps

1. **Create Attachment schema and migration** (`lib/elixirchat/chat/attachment.ex`):
   - Fields: `id`, `message_id`, `filename`, `original_filename`, `content_type`, `size` (bytes)
   - Belongs to Message
   - Add index on message_id

2. **Create database migration**:
   ```bash
   mix ecto.gen.migration create_attachments
   ```
   ```elixir
   create table(:attachments) do
     add :filename, :string, null: false
     add :original_filename, :string, null: false  
     add :content_type, :string, null: false
     add :size, :integer, null: false
     add :message_id, references(:messages, on_delete: :delete_all), null: false
     timestamps()
   end

   create index(:attachments, [:message_id])
   ```

3. **Create file upload module** (`lib/elixirchat/chat/file_upload.ex`):
   - `upload_file/1` - Save uploaded file to storage, return filename
   - `get_upload_path/1` - Get full path for a filename
   - `get_public_url/1` - Get URL for serving the file
   - `validate_file/1` - Check file type and size limits
   - `delete_file/1` - Remove file from storage

4. **Update Message schema** (`lib/elixirchat/chat/message.ex`):
   - Add `has_many :attachments` association
   - Allow messages with only attachments (no text content required)

5. **Update Chat context** (`lib/elixirchat/chat.ex`):
   - Update `send_message/4` to accept optional attachments
   - `attach_files_to_message/2` - Create attachment records for uploaded files
   - Update `list_messages/2` to preload attachments
   - Ensure attachments are included in new message broadcasts

6. **Configure Phoenix for file uploads**:
   - Update `endpoint.ex` to serve static files from uploads directory
   - Set upload limits in `runtime.exs`
   - Create uploads directory in priv/static/

7. **Update ChatLive for file uploads** (`lib/elixirchat_web/live/chat_live.ex`):
   - Add file input with `allow_upload`
   - Handle `"validate"` event for upload validation
   - Update `"send_message"` to process uploads
   - Handle file selection UI state
   - Show upload progress indicator
   - Preview images before sending

8. **Update message rendering in ChatLive**:
   - Display image attachments as thumbnails (max 300px width)
   - Display other files as download links with icon, name, size
   - Add lightbox/modal for full-size image viewing
   - Show file type icons for non-image files

## Technical Details

### Attachment Schema
```elixir
defmodule Elixirchat.Chat.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "attachments" do
    field :filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :size, :integer
    belongs_to :message, Elixirchat.Chat.Message

    timestamps()
  end

  @allowed_types ~w(image/jpeg image/png image/gif image/webp application/pdf text/plain)
  @max_size 10 * 1024 * 1024  # 10MB

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :original_filename, :content_type, :size, :message_id])
    |> validate_required([:filename, :original_filename, :content_type, :size, :message_id])
    |> validate_inclusion(:content_type, @allowed_types, message: "file type not allowed")
    |> validate_number(:size, less_than_or_equal_to: @max_size, message: "file too large (max 10MB)")
    |> foreign_key_constraint(:message_id)
  end

  def allowed_types, do: @allowed_types
  def max_size, do: @max_size
  def max_size_mb, do: div(@max_size, 1024 * 1024)
end
```

### File Upload Module
```elixir
defmodule Elixirchat.Chat.FileUpload do
  @upload_dir "priv/static/uploads"

  def upload_file(upload_entry, consume_fun) do
    # Generate unique filename
    ext = Path.extname(upload_entry.client_name)
    filename = "#{Ecto.UUID.generate()}#{ext}"
    dest = Path.join([@upload_dir, filename])
    
    # Ensure directory exists
    File.mkdir_p!(@upload_dir)
    
    # Consume and save the upload
    consume_fun.(fn %{path: path} ->
      File.cp!(path, dest)
    end)
    
    {:ok, filename}
  end

  def get_public_url(filename) do
    "/uploads/#{filename}"
  end

  def delete_file(filename) do
    path = Path.join([@upload_dir, filename])
    File.rm(path)
  end

  def is_image?(content_type) do
    String.starts_with?(content_type, "image/")
  end
end
```

### LiveView Upload Configuration
```elixir
def mount(params, session, socket) do
  # ... existing mount code ...
  
  {:ok,
   socket
   |> assign(uploads_expanded: false)
   |> allow_upload(:attachments, 
       accept: ~w(.jpg .jpeg .png .gif .webp .pdf .txt),
       max_entries: 5,
       max_file_size: 10_000_000)}
end
```

### UI Components

```heex
<%!-- File upload button next to message input --%>
<div class="flex gap-2">
  <form id="upload-form" phx-change="validate" phx-submit="send_message" class="flex gap-2 flex-1">
    <label class="btn btn-ghost btn-circle cursor-pointer">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
        <path stroke-linecap="round" stroke-linejoin="round" d="m18.375 12.739-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.01.01m5.699-9.941-7.81 7.81a1.5 1.5 0 0 0 2.112 2.13" />
      </svg>
      <.live_file_input upload={@uploads.attachments} class="hidden" />
    </label>
    
    <input type="text" name="message" ... />
    <button type="submit" class="btn btn-primary">Send</button>
  </form>
</div>

<%!-- Upload preview --%>
<div :if={length(@uploads.attachments.entries) > 0} class="flex flex-wrap gap-2 p-2 bg-base-200 rounded-lg mb-2">
  <div :for={entry <- @uploads.attachments.entries} class="relative">
    <.live_img_preview :if={is_image?(entry.client_type)} entry={entry} class="w-20 h-20 object-cover rounded" />
    <div :if={!is_image?(entry.client_type)} class="w-20 h-20 bg-base-300 rounded flex items-center justify-center">
      <span class="text-xs text-center truncate p-1">{entry.client_name}</span>
    </div>
    <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="absolute -top-2 -right-2 btn btn-circle btn-xs btn-error">×</button>
    <progress :if={entry.progress > 0 && entry.progress < 100} value={entry.progress} max="100" class="absolute bottom-0 left-0 w-full h-1" />
  </div>
</div>

<%!-- Image attachment display in message --%>
<div :for={attachment <- message.attachments} class="mt-2">
  <img
    :if={is_image?(attachment.content_type)}
    src={get_attachment_url(attachment)}
    alt={attachment.original_filename}
    class="max-w-xs rounded-lg cursor-pointer hover:opacity-90"
    phx-click="open_image"
    phx-value-url={get_attachment_url(attachment)}
  />
  <a
    :if={!is_image?(attachment.content_type)}
    href={get_attachment_url(attachment)}
    download={attachment.original_filename}
    class="flex items-center gap-2 p-2 bg-base-200 rounded hover:bg-base-300"
  >
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
    </svg>
    <span class="text-sm">{attachment.original_filename}</span>
    <span class="text-xs opacity-50">{format_file_size(attachment.size)}</span>
  </a>
</div>

<%!-- Image lightbox modal --%>
<div :if={@viewing_image} class="modal modal-open" phx-click="close_image">
  <div class="modal-box max-w-4xl">
    <img src={@viewing_image} class="w-full" />
  </div>
  <div class="modal-backdrop"></div>
</div>
```

## Acceptance Criteria
- [ ] Users can select files via attachment button or drag-and-drop
- [ ] Image preview shown before sending
- [ ] Maximum 5 files per message, 10MB each
- [ ] Images display inline as thumbnails in messages
- [ ] Non-image files show as downloadable links
- [ ] Clicking image opens full-size view
- [ ] Upload progress indicator shown
- [ ] Files persist and load after page refresh
- [ ] Attachments appear in real-time for all conversation members
- [ ] Works in both direct and group chats
- [ ] Proper error handling for invalid file types or sizes

## Dependencies
- Task 002: Direct Chat System (completed)
- Task 004: Group Chat System (completed)

## Testing Notes
- Send a message with an image attachment
- Verify image appears as thumbnail in chat
- Click image to view full size
- Send a PDF file and verify it shows as download link
- Try uploading a file over 10MB (should be rejected)
- Try uploading unsupported file type (should be rejected)
- Upload multiple files in one message
- Verify attachments appear for other users in real-time
- Refresh page and verify attachments persist
- Test in both direct and group chats

## Edge Cases to Handle
- User tries to upload file larger than 10MB (show error)
- User tries to upload unsupported file type (show error)
- Network failure during upload (show error, allow retry)
- Message sent with only attachment, no text (should work)
- Image file with wrong extension (validate by content-type)
- Very long filenames (truncate display, preserve on download)
- Message deleted with attachments (cascade delete files)
- Concurrent uploads from multiple users
- Clean up orphaned files (files uploaded but message not sent)

## Future Enhancements (not in this task)
- Cloud storage (S3/R2) for production
- Image compression/resizing
- Video file support with playback
- Audio message recording
- File virus scanning
- Drag-and-drop upload zone
