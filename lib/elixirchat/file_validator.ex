defmodule Elixirchat.FileValidator do
  @moduledoc """
  Validates uploaded files by checking their actual content (magic bytes)
  to prevent malicious files with fake extensions from being uploaded.
  """

  # Image magic bytes
  @jpeg_magic <<0xFF, 0xD8, 0xFF>>
  @png_magic <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
  @gif_magic_87a "GIF87a"
  @gif_magic_89a "GIF89a"
  @webp_magic "RIFF"
  @webp_format "WEBP"

  # Document magic bytes
  @pdf_magic "%PDF"

  # Avatar settings
  @avatar_max_size 2 * 1024 * 1024  # 2MB
  @avatar_allowed_types ~w(image/jpeg image/png image/gif image/webp)
  @avatar_allowed_extensions ~w(.jpg .jpeg .png .gif .webp)

  @doc """
  Validates a file's content matches its claimed type.
  Returns :ok if valid, or {:error, reason} if not.

  ## Parameters
    - path: Path to the file to validate
    - claimed_type: The MIME type claimed by the client (e.g., "image/jpeg")

  ## Examples
      iex> validate_file_content("/tmp/upload.jpg", "image/jpeg")
      :ok

      iex> validate_file_content("/tmp/fake.jpg", "image/jpeg")  # actually a PHP file
      {:error, :invalid_content}
  """
  def validate_file_content(path, claimed_type) do
    case File.read(path) do
      {:ok, content} ->
        if content_matches_type?(content, claimed_type) do
          :ok
        else
          {:error, :invalid_content}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates a file for use as an avatar.
  Checks both the file content and size.

  Returns :ok or {:error, reason}.
  """
  def validate_avatar(path, claimed_type, size) do
    cond do
      size > @avatar_max_size ->
        {:error, :file_too_large}

      claimed_type not in @avatar_allowed_types ->
        {:error, :invalid_type}

      true ->
        validate_file_content(path, claimed_type)
    end
  end

  @doc """
  Returns the maximum avatar file size in bytes.
  """
  def avatar_max_size, do: @avatar_max_size

  @doc """
  Returns the list of allowed avatar MIME types.
  """
  def avatar_allowed_types, do: @avatar_allowed_types

  @doc """
  Returns the list of allowed avatar file extensions.
  """
  def avatar_allowed_extensions, do: @avatar_allowed_extensions

  # Private functions for content validation

  defp content_matches_type?(content, "image/jpeg") do
    match?(@jpeg_magic <> _, content)
  end

  defp content_matches_type?(content, "image/png") do
    match?(@png_magic <> _, content)
  end

  defp content_matches_type?(content, "image/gif") do
    match?(@gif_magic_87a <> _, content) or match?(@gif_magic_89a <> _, content)
  end

  defp content_matches_type?(content, "image/webp") do
    # WebP format: RIFF....WEBP
    case content do
      <<@webp_magic, _size::binary-size(4), @webp_format, _rest::binary>> -> true
      _ -> false
    end
  end

  defp content_matches_type?(content, "application/pdf") do
    match?(@pdf_magic <> _, content)
  end

  defp content_matches_type?(content, "text/plain") do
    # Text files should be valid UTF-8 or ASCII
    String.valid?(content)
  end

  defp content_matches_type?(content, "text/markdown") do
    # Markdown is just text
    String.valid?(content)
  end

  # Unknown type - reject for safety
  defp content_matches_type?(_content, _type), do: false
end
