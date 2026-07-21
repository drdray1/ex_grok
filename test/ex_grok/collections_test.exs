defmodule ExGrok.CollectionsTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Collections, Fixtures}

  @stub_name :collections_test_stub

  describe "management endpoints use the management host" do
    test "create POSTs collection_name to management-api host" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "management-api.x.ai"
        assert conn.method == "POST"
        assert conn.request_path == "/v1/collections"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["collection_name"] == "SEC Filings"
        Req.Test.json(conn, Fixtures.sample_collection())
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, coll} = Collections.create(mgmt, "SEC Filings")
      assert Collections.extract_collection_id(coll) == "coll-xyz"
    end

    test "add_document POSTs to /collections/:id/documents/:file_id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "management-api.x.ai"
        assert conn.method == "POST"
        assert conn.request_path == "/v1/collections/coll-xyz/documents/file-abc123"
        Req.Test.json(conn, %{"ok" => true})
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, %{"ok" => true}} = Collections.add_document(mgmt, "coll-xyz", "file-abc123")
    end

    test "delete removes a collection" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/v1/collections/coll-xyz"
        Req.Test.json(conn, %{"deleted" => true})
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, %{"deleted" => true}} = Collections.delete(mgmt, "coll-xyz")
    end
  end

  describe "remaining management endpoints" do
    test "list, get, update, remove_document" do
      Req.Test.stub(@stub_name, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/v1/collections"} ->
            Req.Test.json(conn, %{"data" => [Fixtures.sample_collection()]})

          {"GET", "/v1/collections/coll-xyz"} ->
            Req.Test.json(conn, Fixtures.sample_collection())

          {"PUT", "/v1/collections/coll-xyz"} ->
            Req.Test.json(conn, %{"updated" => true})

          {"DELETE", "/v1/collections/coll-xyz/documents/file-1"} ->
            Req.Test.json(conn, %{"ok" => true})
        end
      end)

      mgmt = Fixtures.test_management_client(@stub_name)
      assert {:ok, %{"data" => [_]}} = Collections.list(mgmt)
      assert {:ok, %{"collection_id" => "coll-xyz"}} = Collections.get(mgmt, "coll-xyz")

      assert {:ok, %{"updated" => true}} =
               Collections.update(mgmt, "coll-xyz", %{"collection_name" => "New"})

      assert {:ok, %{"ok" => true}} = Collections.remove_document(mgmt, "coll-xyz", "file-1")
    end
  end

  describe "extractors" do
    test "extract_collection_id falls back to id and nil" do
      assert Collections.extract_collection_id(%{"id" => "c1"}) == "c1"
      assert Collections.extract_collection_id(%{}) == nil
    end

    test "extract_search_results handles data key and nil" do
      assert Collections.extract_search_results(%{"data" => [1]}) == [1]
      assert Collections.extract_search_results(%{}) == []
    end
  end

  describe "search uses the normal inference host" do
    test "omits source when no collection_ids and honors limit" do
      Req.Test.expect(@stub_name, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        refute Map.has_key?(params, "source")
        assert params["limit"] == 5
        assert params["retrieval_mode"] == %{"type" => "semantic"}
        Req.Test.json(conn, Fixtures.sample_search_results())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, _} = Collections.search(client, "q", retrieval_mode: "semantic", limit: 5)
    end

    test "POSTs query + collection_ids to /documents/search on api.x.ai" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.host == "api.x.ai"
        assert conn.request_path == "/v1/documents/search"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        assert params["query"] == "revenue"
        assert params["source"] == %{"collection_ids" => ["coll-xyz"]}
        assert params["retrieval_mode"] == %{"type" => "hybrid"}
        Req.Test.json(conn, Fixtures.sample_search_results())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, resp} = Collections.search(client, "revenue", collection_ids: ["coll-xyz"])
      assert [%{"file_id" => "file-abc123"}] = Collections.extract_search_results(resp)
    end
  end
end
