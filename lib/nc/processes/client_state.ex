defmodule Nc.Processes.ClientState do
  # the definition of the client state are done here, as well as all of the functions for manipulating the state

  # state should not be entirely encapsulated within this module however, as that would complicate sending messages & reading

  alias Nc.Sync
  alias Nc.Core.DocTree

  @type t() :: %{
          document: DocTree.t(),
          pending: [Sync.change()],
          last_pulled: non_neg_integer(),
          server: pid()
        }

  @spec new(pid(), DocTree.t(), non_neg_integer()) :: t()
  def new(server_pid, doctree, last_pulled) do
    %{
      document: doctree,
      pending: [],
      last_pulled: last_pulled,
      server: server_pid
    }
  end

  defp apply_change(document, change) do
    case change do
      {:insert, position, text, _from} ->
        DocTree.insert(document, position, text)

      {:delete, position, amount, _from} ->
        DocTree.delete(document, position, amount)

      nil ->
        document
    end
  end

  defp apply_change_list(document, change_list) do
    Enum.reduce(change_list, document, &apply_change(&2, &1))
  end

  @spec make_change(t(), Sync.change()) :: t()
  def make_change(state, change) do
    %{
      state
      | document: apply_change(state.document, change),
        pending: state.pending ++ [change]
    }
  end

  @spec start_pull(t()) :: {t(), non_neg_integer()}
  def start_pull(state) do
    {
      state,
      state.last_pulled
    }
  end

  @spec recieve_pull(t(), [Sync.change()], non_neg_integer()) :: t()
  def recieve_pull(state, incoming_change_list, version) do
    {changes_to_apply, new_pending_changes} =
      Sync.reconcile_against(incoming_change_list, state.pending)

    new_document = apply_change_list(state.document, changes_to_apply)

    %{
      state
      | document: new_document,
        pending: new_pending_changes,
        last_pulled: version
    }
  end

  @spec start_push(t()) :: {t(), [Sync.change()]}
  def start_push(state) do
    {
      %{
        state
        | pending: []
      },
      state.pending
    }
  end

  # these operations are made to run asynchronously, and so we should assume new changes have been added pending changes to since the request to pull has been sent
end
