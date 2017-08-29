defmodule UccChat.Channel do
  use UccModel, schema: UccChat.Schema.Channel

  import Ecto.Changeset

  alias UcxUcc.{Accounts, Accounts.User,  Repo}
  alias UccChat.Subscription
  alias UccChat.Schema.Subscription, as: SubscriptionSchema
  alias UccChat.Schema.Channel, as: ChannelSchema

  require Logger

  def changeset(user, params) do
    changeset %@schema{}, user, params
  end

  def changeset(struct, user, params) do
    struct
    |> @schema.changeset(params)
    |> validate_permission(user)
  end

  def changeset_settings(struct, user, [{"private", value}]) do
    type = if value == true, do: 1, else: 0
    changeset(struct, user, %{type: type})
  end

  def changeset_settings(struct, user, [{field, value}]) do
    changeset(struct, user, %{field => value})
  end

  defdelegate changeset_delete(struct, params \\ %{}), to: @schema

  defdelegate changeset_update(struct, params \\ %{}), to: @schema

  defdelegate blocked_changeset(struct, blocked), to: @schema

  def validate_permission(%{changes: changes, data: data} = changeset, user) do
    # Logger.warn "validate_permission: changeset: #{inspect changeset}, type: #{inspect changeset.data.type}"
    cond do
      changes[:type] != nil -> has_permission?(user, changes)
      true -> has_permission?(user, data)
    end
    |> case do
      true -> changeset
      _ ->
        add_error(changeset, :user, "permission denied")
    end
  end

  def has_permission?(_, _), do: true
  # defp has_permission?(user, %{type: 1}), do: Permissions.has_permission?(user, "create-p")
  # defp has_permission?(user, %{type: 2}), do: Permissions.has_permission?(user, "create-d")
  # defp has_permission?(user, _), do: Permissions.has_permission?(user, "create-c")

  def total_rooms do
    from c in @schema, select: count(c.id)
  end

  def get_total_rooms do
    Repo.one total_rooms()
  end

  def total_rooms(type) do
    from c in @schema, where: c.type == ^type, select: count(c.id)
  end

  def total_channels do
    total_rooms 0
  end

  def get_total_channels do
    Repo.one total_channels()
  end

  def total_private do
    total_rooms 1
  end

  def get_total_private do
    Repo.one total_private()
  end

  def total_direct do
    total_rooms 2
  end

  def get_total_direct do
    Repo.one total_direct()
  end

  def get_all_channels do
    from c in @schema, where: c.type in [0,1]
  end

  def get_all_public_channels do
    from c in @schema, where: c.type == 0
  end

  def get_authorized_channels(user_id) do
    user = UccChat.ServiceHelpers.get_user!(user_id)
    cond do
      User.has_role?(user, "admin") ->
        from c in @schema, where: c.type == 0 or c.type == 1
      User.has_role?(user, "user") ->
        from c in @schema,
          left_join: s in SubscriptionSchema, on: s.channel_id == c.id and s.user_id == ^user_id,
          where: (c.type == 0 or (c.type == 1 and not is_nil(s.id))) and (not s.hidden or c.user_id == ^user_id)
      true -> from c in @schema, where: false
    end
  end


  # all puplic and
  # privates that I'm subscribed too
  # and all channels I own
  def get_all_channels(%User{id: user_id} = user) do
    cond do
      User.has_role?(user, "admin") ->
        from c in @schema, where: c.type == 0 or c.type == 1, preload: [:subscriptions]
      User.has_role?(user, "user") ->
        from c in @schema,
          left_join: s in SubscriptionSchema, on: s.channel_id == c.id and s.user_id == ^user_id,
          where: c.type == 0 or (c.type == 1 and s.user_id == ^user_id) or c.user_id == ^user_id
      true -> from c in @schema, where: false
    end
  end

  def get_all_channels(user_id) do
    user_id
    |> UccChat.ServiceHelpers.get_user!
    |> get_all_channels
  end

  def get_channels_by_pattern(user_id, pattern, count \\ 5) do
    user_id
    |> get_authorized_channels
    |> where([c], like(c.name, ^pattern))
    |> order_by([c], asc: c.name)
    |> limit(^count)
    |> select([c], {c.id, c.name})
    |> @repo.all
  end

  def room_route(channel) do
    case channel.type do
      ch when ch in [0,1] -> "channels"
      _ -> "direct"
    end
  end

  def direct?(channel) do
    channel.type == 2
  end

  def subscription_status(%{subscriptions: subs} = _channel, user_id) when is_list(subs) do
    Enum.reduce subs, {false, false}, fn
      %{user_id: ^user_id, hidden: hidden}, _acc -> {true, hidden}
      _, acc -> acc
    end
  end

  def subscription_status(channel, user_id) do
    channel
    |> @repo.preload([:subscriptions])
    |> subscription_status(user_id)
  end

  def list_by_default(default) do
    @repo.all from c in @schema, where: c.default == ^default
  end

  def archive(%ChannelSchema{archived: true} = channel, user_id) do
    Logger.error ""
    changeset =
      channel
      |> changeset(get_user!(user_id), %{archived: true})
      |> add_error(:archived, "already archived")
    {:error, changeset}
  end

  def archive(%ChannelSchema{id: id} = channel, user_id) do
    Logger.error ""
    channel
    |> changeset(get_user!(user_id), %{archived: true})
    |> update
    |> case do
      {:ok, _channel} = response ->
        Subscription.update_all_hidden(id, true)
        response
      {:error, changeset} = response ->
        Logger.warn "error archiving channel #{inspect changeset.errors}"
        response
    end
  end

  def unarchive(%ChannelSchema{archived: false} = channel, user_id) do
    Logger.error ""
    changeset =
      channel
      |> changeset(get_user!(user_id), %{archived: false})
      |> add_error(:archived, "not archived")
    {:error, changeset}
  end

  def unarchive(%ChannelSchema{id: id} = channel, user_id) do
    Logger.error ""
    channel
    |> changeset(get_user!(user_id), %{archived: false})
    |> update
    |> case do
      {:ok, _channel} = response ->
        Subscription.update_all_hidden(id, false)
        response
      {:error, changeset} = response ->
        Logger.warn "error unarchiving channel #{inspect changeset.errors}"
        response
    end
  end

  defp get_user!(user_id) do
    Accounts.get_user! user_id, preload: [:roles]
  end

end
