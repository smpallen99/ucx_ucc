defmodule OneBackupRestoreWeb.Admin.Page.BackupRestore do
  @moduledoc """
  Backup and Restore plug-in Admin page.
  """
  use OneAdmin.Page

  import InfinityOneWeb.Gettext

  alias InfinityOne.{Repo, Hooks}
  alias OneChatWeb.RebelChannel.Client
  alias OneBackupRestore.Utils
  alias OneChat.ServiceHelpers

  require Logger

  def add_page do
    new(
      "admin_backup_restore",
      __MODULE__,
      ~g(Backup and Restore),
      OneBackupRestoreWeb.AdminView,
      "backup_restore.html",
      53,
      pre_render_check: &check_perissions/2,
      permission: "view-backup-restore-administration"
    )
  end

  def args(page, user, _sender, socket) do
    {[
      user: Repo.preload(user, Hooks.user_preload([])),
      backups: OneBackupRestore.get_backups()
    ], user, page, socket}
  end

  def admin_restore_backup(socket, _sender) do
    socket
  end

  def admin_delete_backup(socket, sender) do
    id = sender["dataset"]["id"]
    Client.swal_modal(
      socket,
      ~g(Delete Backup),
      gettext("Are you sure do delete %{id}? This cannot be undone!", id: id),
      "warning",
      ~g(Delete Backup!),
        confirm: fn _result ->
          {title, text, type} =
            case Utils.delete_backup(id) do
              {:error, message} ->
                {
                  ~g(Oops, something went wrong!),
                  gettext("Error: %{message}.", message: message),
                  "error"
                }
              _ ->
                {
                  ~g(Success!),
                  ~g(Backup file removed successfully),
                  "success"
                }
            end
          Client.swal(socket, title, text, type)
          if type == "success" do
            remove_row(socket, id)
          end
          socket
        end
      )
    socket
  end

  def admin_backup_batch_delete(socket, %{"form" => form}) do
    params = ServiceHelpers.normalize_params(form)["backup"] || %{}

    backups =
      params
      |> Enum.filter(& elem(&1, 1) == "true")
      |> Enum.map(& elem(&1, 0))

    Client.swal_modal(
      socket,
      ~g(Delete Backups),
      ~g(Are you sure you want to delete the selected backups? This cannot be undone!),
      "warning",
      ~g(Delete Backups!),
      confirm: fn _ ->
        case Utils.batch_delete_backups(backups) do
          {:ok, list} ->
            Client.swal(socket, ~g(Success!), ~g(Backup files removed successfully), "success")
            list
          {:error, list} ->
            Client.swal(socket, ~g(Error!), ~g(One or more of the files wern't removed), "error")
            list
        end
        |> Enum.each(&remove_named_row(socket, &1))
        Rebel.Core.async_js(socket, ~s/$('#batch-delete').attr('disabled', true)/)
      end
    )
    socket
  end

  defp remove_row(socket, id) do
    spawn fn ->
      name = Path.rootname(id)
      js = """
        var target = $('[download="#{name}"]').closest('tr');
        target.hide('slow', function() { target.remove(); });
        """ |> String.replace("\n", "")
      Rebel.Core.async_js(socket, js)
    end
    socket
  end

  defp remove_named_row(socket, name) do
    spawn fn ->
      js = """
        var target = $('[name="backup[#{name}]"]').closest('tr');
        target.hide('slow', function() { target.remove(); });
        """ |> String.replace("\n", "")
      Rebel.Core.async_js(socket, js)
    end
  end

  def check_perissions(_page, user) do
    has_permission? user, "view-backup-restore-administration"
  end
end
