defmodule MyMacros do
  defmacro myunless(expr, opts) do
    quote do
      if(!unquote(expr), unquote(opts))
    end
  end
end

# Code.require_file "macros.exs"
# import MyMacros

# myunless 1 + 2 != 3, do: "it works", else: raise("this is never evaluated")
