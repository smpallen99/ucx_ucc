defmodule UccChat.AttachmentService do
  use UccChat.Shared, :service

  alias UccChat.{Attachment, Message, MessageService, Channel}
  alias Ecto.Multi

  require Logger

  def insert_attachment(params) do
    message_params = %{channel_id: params["channel_id"], body: "", sequential: false, user_id: params["user_id"]}
    params = Map.delete params, "user_id"
    multi =
      Multi.new
      |> Multi.insert(:message, Message.changeset(%Message{}, message_params))
      |> Multi.run(:attachment, &do_insert_attachment(&1, params))

    case Repo.transaction(multi) do
      {:ok, %{message: message}} = ok ->
        broadcast_message(message)
        ok
      error ->
        error
    end
  end

  defp do_insert_attachment(%{message: %{id: id} = message}, params) do
    changeset = Attachment.changeset(%Attachment{}, Map.put(params, "message_id", id))
    case Repo.insert changeset do
      {:ok, attachment} ->
        {:ok, %{attachment: attachment, message: message}}
      error -> error
    end
  end

  def delete_attachment(%Attachment{} = attachment) do
    case Repo.delete attachment do
      {:ok, _} = res ->
        path = UccChat.File.storage_dir(attachment)
        File.rm_rf path
        res
      error -> error
    end
  end

  defp broadcast_message(message) do
    channel = Helpers.get Channel, message.channel_id
    html =
      message
      |> Repo.preload(MessageService.preloads())
      |> MessageService.render_message
    MessageService.broadcast_message(message.id, channel.name, message.user_id, html)
  end

  def count(message_id) do
    Repo.one from a in Attachment,
      where: a.message_id == ^message_id,
      select: count(a.id)
  end

  def allowed?(channel) do
    UccSettings.file_uploads_enabled() && ((channel.type != 2) || UccSettings.dm_file_uploads())
  end
end
