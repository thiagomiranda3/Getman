package br.com.tommiranda;

import javafx.application.Application;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Stage;

import java.io.IOException;

public class AppLauncher extends Application {

    @Override
    public void start(Stage primaryStage) throws IOException {
        FXMLLoader loader = new FXMLLoader(getClass().getResource("/main.fxml"));
        Parent root = loader.load();
        Scene scene = new Scene(root, 800, 600);
        scene.getStylesheets().add(getClass().getResource("/json-highlighting.css").toExternalForm());
        primaryStage.setTitle("TomTools - Postman Replica");
        primaryStage.setScene(scene);
        primaryStage.show();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
