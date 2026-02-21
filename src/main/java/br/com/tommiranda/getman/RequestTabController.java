package br.com.tommiranda.getman;

import com.fasterxml.jackson.databind.ObjectMapper;
import javafx.collections.FXCollections;
import javafx.fxml.FXML;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.StackPane;
import org.fxmisc.richtext.CodeArea;
import org.fxmisc.richtext.LineNumberFactory;
import org.fxmisc.richtext.model.StyleSpans;
import org.fxmisc.richtext.model.StyleSpansBuilder;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Collection;
import java.util.Collections;
import java.util.concurrent.CompletableFuture;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class RequestTabController {

    @FXML
    private ComboBox<String> methodComboBox;

    @FXML
    private TextField urlField;

    @FXML
    private StackPane requestBodyContainer;

    @FXML
    private HeadersComponentController requestHeadersController;

    @FXML
    private StackPane responseBodyContainer;

    @FXML
    private HeadersComponentController responseHeadersController;

    @FXML
    private Label statusLabel;

    @FXML
    private Label timeLabel;

    @FXML
    private Label sizeLabel;

    private CodeArea requestBodyCodeArea;
    private CodeArea responseBodyCodeArea;

    private final HttpClient httpClient = HttpClient.newBuilder()
                                                    .version(HttpClient.Version.HTTP_2)
                                                    .connectTimeout(Duration.ofSeconds(10))
                                                    .build();

    private final ObjectMapper objectMapper = new ObjectMapper();

    private static final Pattern JSON_PATTERN = Pattern.compile(
            "(?<BRACE>\\{|\\})|" +
            "(?<BRACKET>\\[|\\])|" +
            "(?<COMMA>,)|" +
            "(?<COLON>:)|" +
            "(?<STRING>\"([^\"\\\\]|\\\\.)*\")|" +
            "(?<NUMBER>\\b\\d+(\\.\\d+)?\\b)|" +
            "(?<BOOLEAN>\\b(true|false|null)\\b)"
    );

    private String tabId;
    private StateManager stateManager;

    public void setTabId(String tabId) {
        this.tabId = tabId;
    }

    public void setStateManager(StateManager stateManager) {
        this.stateManager = stateManager;
    }

    @FXML
    public void initialize() {
        methodComboBox.setItems(FXCollections.observableArrayList("GET", "POST", "PUT", "DELETE", "PATCH"));
        methodComboBox.getSelectionModel().select("GET");

        requestBodyCodeArea = new CodeArea();
        requestBodyCodeArea.setParagraphGraphicFactory(LineNumberFactory.get(requestBodyCodeArea));
        requestBodyCodeArea.textProperty().addListener((obs, oldText, newText) -> {
            requestBodyCodeArea.setStyleSpans(0, computeHighlighting(newText));
        });
        requestBodyContainer.getChildren().add(requestBodyCodeArea);

        responseBodyCodeArea = new CodeArea();
        responseBodyCodeArea.setEditable(false);
        responseBodyCodeArea.setParagraphGraphicFactory(LineNumberFactory.get(responseBodyCodeArea));
        responseBodyCodeArea.textProperty().addListener((obs, oldText, newText) -> {
            responseBodyCodeArea.setStyleSpans(0, computeHighlighting(newText));
        });
        responseBodyContainer.getChildren().add(responseBodyCodeArea);

        // Set default headers
        requestHeadersController.setHeadersText("Content-Type: application/json\nAccept: application/json");

        // Set response headers to read-only
        responseHeadersController.setReadOnly(true);
    }

    public void loadState(RequestData data) {
        if (data == null) {
            return;
        }

        if (data.getMethod() != null) {
            methodComboBox.setValue(data.getMethod());
        }
        if (data.getUrl() != null) {
            urlField.setText(data.getUrl());
        }
        if (data.getRequestBody() != null) {
            requestBodyCodeArea.replaceText(data.getRequestBody());
        }
        if (data.getRequestHeaders() != null) {
            requestHeadersController.setHeadersText(data.getRequestHeaders());
        }

        if (data.getResponseBody() != null) {
            responseBodyCodeArea.replaceText(data.getResponseBody());
        }
        if (data.getResponseHeaders() != null) {
            responseHeadersController.setHeadersText(data.getResponseHeaders());
        }

        if (data.getStatus() != null) {
            statusLabel.setText(data.getStatus());
        }
        if (data.getTime() != null) {
            timeLabel.setText(data.getTime());
        }
        if (data.getSize() != null) {
            sizeLabel.setText(data.getSize());
        }
    }

    public void saveState() {
        if (stateManager == null || tabId == null) {
            return;
        }

        RequestData data = new RequestData();
        data.setId(tabId);
        data.setMethod(methodComboBox.getValue());
        data.setUrl(urlField.getText());
        data.setRequestBody(requestBodyCodeArea.getText());
        data.setRequestHeaders(requestHeadersController.getHeadersText());
        data.setResponseBody(responseBodyCodeArea.getText());
        data.setResponseHeaders(responseHeadersController.getHeadersText());
        data.setStatus(statusLabel.getText());
        data.setTime(timeLabel.getText());
        data.setSize(sizeLabel.getText());

        CompletableFuture.runAsync(() -> stateManager.saveRequestData(data));
    }

    @FXML
    public void handleSendRequest() {
        String url = urlField.getText();
        String method = methodComboBox.getValue();
        String body = requestBodyCodeArea.getText();
        String headersText = requestHeadersController.getHeadersText();

        try {
            if (url == null || url.isEmpty()) {
                responseBodyCodeArea.replaceText("Error: URL cannot be empty");
                statusLabel.setText("Status: Error");
                timeLabel.setText("Time: ");
                sizeLabel.setText("Size: ");
                return;
            }

            HttpRequest.Builder requestBuilder = HttpRequest.newBuilder()
                                                            .uri(URI.create(url))
                                                            .timeout(Duration.ofMinutes(1));

            // Add headers
            if (headersText != null && !headersText.isEmpty()) {
                String[] lines = headersText.split("\\n");
                for (String line : lines) {
                    String[] parts = line.split(":", 2);
                    if (parts.length == 2) {
                        requestBuilder.header(parts[0].trim(), parts[1].trim());
                    }
                }
            }

            // Set method and body
            switch (method) {
                case "GET":
                    requestBuilder.GET();
                    break;
                case "POST":
                    requestBuilder.POST(HttpRequest.BodyPublishers.ofString(body != null ? body : ""));
                    break;
                case "PUT":
                    requestBuilder.PUT(HttpRequest.BodyPublishers.ofString(body != null ? body : ""));
                    break;
                case "DELETE":
                    requestBuilder.DELETE();
                    break;
                case "PATCH":
                    requestBuilder.method("PATCH", HttpRequest.BodyPublishers.ofString(body != null ? body : ""));
                    break;
            }

            HttpRequest request = requestBuilder.build();

            statusLabel.setText("Status: Sending...");
            timeLabel.setText("Time: ...");
            sizeLabel.setText("Size: ...");
            responseBodyCodeArea.replaceText("");
            responseHeadersController.setHeadersText("");

            long startTime = System.currentTimeMillis();

            httpClient.sendAsync(request, HttpResponse.BodyHandlers.ofString())
                      .thenApply(response -> {
                          long endTime = System.currentTimeMillis();
                          long duration = endTime - startTime;
                          String bodyText = response.body();
                          int size = bodyText.getBytes().length;

                          javafx.application.Platform.runLater(() -> {
                              statusLabel.setText("Status: " + response.statusCode());
                              timeLabel.setText("Time: " + duration + " ms");
                              sizeLabel.setText("Size: " + size + " bytes");
                              StringBuilder headersSb = new StringBuilder();
                              response.headers().map().forEach((k, v) -> headersSb.append(k).append(": ").append(v).append("\n"));
                              responseHeadersController.setHeadersText(headersSb.toString());
                          });
                          return bodyText;
                      })
                      .thenAccept(responseString -> {
                          String formattedResponse = responseString;
                          try {
                              Object json = objectMapper.readValue(responseString, Object.class);
                              formattedResponse = objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(json);
                          } catch (Exception e) {
                              // Not a valid JSON or empty, keep original string
                          }
                          String finalResponse = formattedResponse;
                          javafx.application.Platform.runLater(() -> {
                              responseBodyCodeArea.replaceText(finalResponse);
                          });
                      })
                      .exceptionally(e -> {
                          long endTime = System.currentTimeMillis();
                          long duration = endTime - startTime;
                          javafx.application.Platform.runLater(() -> {
                              statusLabel.setText("Status: Error");
                              timeLabel.setText("Time: " + duration + " ms");
                              sizeLabel.setText("Size: ");
                              responseBodyCodeArea.replaceText("Error: " + e.getMessage());
                          });
                          return null;
                      });

        } catch (Exception e) {
            statusLabel.setText("Status: Error");
            timeLabel.setText("Time: ");
            sizeLabel.setText("Size: ");
            responseBodyCodeArea.replaceText("Error building request: " + e.getMessage());
        } finally {
            saveState();
        }
    }

    private static StyleSpans<Collection<String>> computeHighlighting(String text) {
        Matcher matcher = JSON_PATTERN.matcher(text);
        int lastKwEnd = 0;
        StyleSpansBuilder<Collection<String>> spansBuilder = new StyleSpansBuilder<>();
        while (matcher.find()) {
            String styleClass =
                    matcher.group("BRACE") != null ? "brace" :
                            matcher.group("BRACKET") != null ? "bracket" :
                                    matcher.group("COMMA") != null ? "comma" :
                                            matcher.group("COLON") != null ? "colon" :
                                                    matcher.group("STRING") != null ? "string" :
                                                            matcher.group("NUMBER") != null ? "number" :
                                                                    matcher.group("BOOLEAN") != null ? "boolean" :
                                                                            null; /* never happens */
            assert styleClass != null;
            spansBuilder.add(Collections.emptyList(), matcher.start() - lastKwEnd);
            spansBuilder.add(Collections.singleton(styleClass), matcher.end() - matcher.start());
            lastKwEnd = matcher.end();
        }
        spansBuilder.add(Collections.emptyList(), text.length() - lastKwEnd);
        return spansBuilder.create();
    }
}
