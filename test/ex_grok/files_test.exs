defmodule ExGrok.FilesTest do
  use ExUnit.Case, async: true

  alias ExGrok.{Files, Fixtures}

  @stub_name :files_test_stub

  describe "upload/3" do
    test "POSTs multipart to /files with file + purpose" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/files"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "report.pdf"
        assert body =~ "collections"
        Req.Test.json(conn, Fixtures.sample_file())
      end)

      client = Fixtures.test_client(@stub_name)

      assert {:ok, file} =
               Files.upload(client, {:content, "PDFDATA", "report.pdf"}, purpose: "collections")

      assert Files.extract_file_id(file) == "file-abc123"
    end
  end

  describe "list/1, get/2, content/2, delete/2" do
    test "list returns files" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/files"
        Req.Test.json(conn, Fixtures.sample_files_list())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, resp} = Files.list(client)
      assert [%{"id" => "file-abc123"}] = Files.extract_files(resp)
    end

    test "get retrieves metadata by id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/files/file-abc123"
        Req.Test.json(conn, Fixtures.sample_file())
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"filename" => "report.pdf"}} = Files.get(client, "file-abc123")
    end

    test "content downloads raw bytes" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.request_path == "/v1/files/file-abc123/content"
        Plug.Conn.send_resp(conn, 200, "RAWFILE")
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, "RAWFILE"} = Files.content(client, "file-abc123")
    end

    test "delete removes by id" do
      Req.Test.expect(@stub_name, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/v1/files/file-abc123"
        Req.Test.json(conn, %{"id" => "file-abc123", "deleted" => true})
      end)

      client = Fixtures.test_client(@stub_name)
      assert {:ok, %{"deleted" => true}} = Files.delete(client, "file-abc123")
    end
  end
end
