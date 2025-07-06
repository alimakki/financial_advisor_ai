defmodule FinancialAdvisorAi.Integrations.GmailServiceTest do
  use FinancialAdvisorAi.DataCase, async: true

  # alias FinancialAdvisorAi.Repo
  # alias FinancialAdvisorAi.AI.EmailEmbedding
  alias FinancialAdvisorAi.Integrations.GmailService

  describe "email service" do
    test "create text embedding" do
      # create test user
      {:ok, user} =
        FinancialAdvisorAi.Accounts.register_user(%{
          email: "test@example.com"
        })

      # example email data
      email_data = %{
        "id" => "18c1234567890abcdef",
        "threadId" => "18c1234567890abcdef",
        "labelIds" => ["INBOX", "UNREAD"],
        "payload" => %{
          "partId" => "",
          "mimeType" => "text/plain",
          "filename" => "",
          "headers" => [
            %{"name" => "Delivered-To", "value" => "test@example.com"},
            %{
              "name" => "Received",
              "value" =>
                "by 2002:a05:6a00:1234:0:0:0:0 with SMTP id x123; Mon, 15 Jan 2024 10:30:00 -0800 (PST)"
            },
            %{
              "name" => "X-Google-Smtp-Source",
              "value" => "ABcdEFghIJklMNopQRstUVwxYZ1234567890"
            },
            %{
              "name" => "X-Received",
              "value" =>
                "by 2002:a05:6a00:1234:0:0:0:0 with SMTP id x123; Mon, 15 Jan 2024 10:30:00 -0800 (PST)"
            },
            %{
              "name" => "ARC-Seal",
              "value" =>
                "i=1; a=rsa-sha256; t=1705338600; cv=none; d=google.com; s=arc-20160816; b=ABC123..."
            },
            %{
              "name" => "ARC-Message-Signature",
              "value" =>
                "i=1; a=rsa-sha256; t=1705338600; c=relaxed/relaxed; d=google.com; s=arc-20160816; h=message-id:date:from:to:subject; bh=ABC123..."
            },
            %{
              "name" => "ARC-Authentication-Results",
              "value" =>
                "i=1; mx.google.com; dkim=pass header.i=@example.com header.s=20221201 header.b=ABC123...; spf=pass (google.com: domain of sender@example.com designates 192.168.1.1 as permitted sender) smtp.mailfrom=sender@example.com; dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=example.com"
            },
            %{"name" => "Return-Path", "value" => "<sender@example.com>"},
            %{
              "name" => "Received",
              "value" =>
                "from mail-wr1-f54.google.com (mail-wr1-f54.google.com [192.168.1.1]) by smtp.gmail.com (Postfix) with ESMTPS id 1234567890 for <user@example.com>; Mon, 15 Jan 2024 10:30:00 -0800 (PST)"
            },
            %{
              "name" => "Received-SPF",
              "value" =>
                "Pass (sender SPF authorized) identity=mailfrom; client-ip=192.168.1.1; helo=mail-wr1-f54.google.com; envelope-from=sender@example.com; x-sender=sender@example.com; x-recipient=user@example.com"
            },
            %{
              "name" => "Authentication-Results",
              "value" =>
                "mx.google.com; dkim=pass header.i=@example.com header.s=20221201 header.b=ABC123...; spf=pass (google.com: domain of sender@example.com designates 192.168.1.1 as permitted sender) smtp.mailfrom=sender@example.com; dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=example.com"
            },
            %{
              "name" => "X-Google-DKIM-Signature",
              "value" =>
                "v=1; a=rsa-sha256; c=relaxed/relaxed; d=gmail.com; s=20221201; h=message-id:date:from:to:subject; bh=ABC123...; b=ABC123..."
            },
            %{"name" => "X-Gm-Message-State", "value" => "AOAM5324X1234567890"},
            %{
              "name" => "X-Google-Smtp-Source",
              "value" => "ABcdEFghIJklMNopQRstUVwxYZ1234567890"
            },
            %{"name" => "MIME-Version", "value" => "1.0"},
            %{
              "name" => "X-Received",
              "value" =>
                "by 2002:a05:6a00:1234:0:0:0:0 with SMTP id x123; Mon, 15 Jan 2024 10:30:00 -0800 (PST)"
            },
            %{"name" => "From", "value" => "John Doe <john.doe@example.com>"},
            %{"name" => "Date", "value" => "Mon, 15 Jan 2024 10:30:00 -0800"},
            %{"name" => "Message-ID", "value" => "<1234567890.1234567890@example.com>"},
            %{"name" => "Subject", "value" => "Meeting Tomorrow - Financial Planning Discussion"},
            %{"name" => "To", "value" => "user@example.com"},
            %{"name" => "Content-Type", "value" => "text/plain; charset=UTF-8"},
            %{"name" => "Content-Transfer-Encoding", "value" => "quoted-printable"}
          ],
          "body" => %{
            "attachmentId" => "",
            "size" => 1024,
            "data" =>
              "SGVsbG8sCgpJIGhvcGUgdGhpcyBlbWFpbCBmaW5kcyB5b3Ugd2VsbC4gSSB3b3VsZCBsaWtlIHRvIGRpc2N1c3Mgb3VyIGZpbmFuY2lhbCBwbGFubmluZyBzdHJhdGVneSB0b21vcnJvdyBhdCAyOjAwIFBNLgoKSW4gdGhpcyBtZWV0aW5nLCB3ZSB3aWxsIGNvdmVyOgoKLSAgUmV0aXJlbWVudCBwbGFubmluZwotICBJbnZlc3RtZW50IHN0cmF0ZWd5CgotICBUYXggb3B0aW1pemF0aW9uCgotICBJbnN1cmFuY2UgcmV2aWV3CgpQbGVhc2UgYnJpbmcgeW91ciBxdWVzdGlvbnMgYW5kIGFueSBkb2N1bWVudHMgdGhhdCBtaWdodCBiZSBoZWxwZnVsLgoKQmVzdCByZWdhcmRzLApKb2huIERvZQpGaW5hbmNpYWwgQWR2aXNvcg=="
          }
        },
        "sizeEstimate" => 2048,
        "historyId" => "123456789",
        "internalDate" => "1751840267"
      }

      parsed = GmailService.parse_message(email_data)

      # create test email
      {:ok, contact} = GmailService.create_contact_from_email(user.id, parsed)

      # check if contact was created
      assert contact.id != nil
    end
  end
end
