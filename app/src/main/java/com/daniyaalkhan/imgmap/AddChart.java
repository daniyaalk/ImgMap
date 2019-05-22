package com.daniyaalkhan.imgmap;

import android.content.Intent;
import android.net.Uri;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;

public class AddChart extends AppCompatActivity {

    private Uri selectedFile;
    private ImageView chartView;
    private Button confirmButton;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_chart);

        //Get ICAO from Extras
        Bundle extras = getIntent().getExtras();
        final String icao = extras.getString("icao");

        final Button addImageButton = findViewById(R.id.addImage);
        this.confirmButton = findViewById(R.id.confirm);

        this.chartView = findViewById(R.id.chartView);
        this.chartView.setScaleType(ImageView.ScaleType.CENTER_INSIDE);

        final Intent getImage = new Intent();
        getImage.setAction(Intent.ACTION_GET_CONTENT);
        getImage.setType("image/*");

        addImageButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivityForResult(Intent.createChooser(getImage, "Select an Image"), 123);
            }
        });

        confirmButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent addPoints = new Intent(getApplicationContext(), AddPoints.class);
                addPoints.putExtra("icao", icao);
                addPoints.putExtra("uri", selectedFile.toString());
                startActivity(addPoints);
            }
        });

    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if(requestCode == 123 && resultCode == RESULT_OK) {
            this.selectedFile = data.getData(); //The uri with the location of the file
            Log.d("FileURI", data.getData().toString());
            this.chartView.setImageURI(this.selectedFile);
            this.confirmButton.setEnabled(true);
        }
    }


}
