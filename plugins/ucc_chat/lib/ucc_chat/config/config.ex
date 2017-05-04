defmodule UccChat.Config do
  use UccChat.Shared, :schema

  alias UcxUcc.Repo

  @mod __MODULE__

  schema "config" do
    embeds_one :general, UccChat.Config.General
    embeds_one :message, UccChat.Config.Message
    embeds_one :layout, UccChat.Config.Layout
    embeds_one :file_upload, UccChat.Config.FileUpload

    timestamps()
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [])
    |> cast_embed(:general)
    |> cast_embed(:message)
    |> cast_embed(:layout)
    |> cast_embed(:file_upload)
    |> validate_required([:general, :message, :layout, :file_upload])
  end

  def new_changeset do
    params =
      :embeds
      |> @mod.__schema__
      |> Enum.map(&(@mod.__schema__(:embed, &1)))
      |> Enum.reduce(%{}, fn %Ecto.Embedded{field: field, related: related}, acc ->
        Map.put(acc, field, related.__struct__ |> Map.from_struct)
      end)
    changeset(@mod.__struct__, params)
  end

  def update! do
    @mod |> Repo.one |> Repo.delete()
    Repo.insert new_changeset()
  end
end
