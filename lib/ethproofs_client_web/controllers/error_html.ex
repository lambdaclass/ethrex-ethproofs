defmodule EthProofsClientWeb.ErrorHTML do
  @moduledoc """
  Error page templates.
  """
  use EthProofsClientWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
