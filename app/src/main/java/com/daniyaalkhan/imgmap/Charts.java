package com.daniyaalkhan.imgmap;

import android.content.Intent;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.ListView;

import java.util.List;

public class Charts extends AppCompatActivity {

    private ListView chartsListView;
    private String icao;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_charts);

        this.chartsListView = findViewById(R.id.chatsList);

        Bundle extras = getIntent().getExtras();
        this.icao = extras.getString("icao");

        Button addChartButton = findViewById(R.id.addChart);
        addChartButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                //TODO
                Intent addChartIntent = new Intent(getApplicationContext(), AddChart.class);
                addChartIntent.putExtra("icao", icao);
                startActivity(addChartIntent);
            }
        });
    }
}
