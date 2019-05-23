package com.daniyaalkhan.imgmap;

import android.content.Intent;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.ListAdapter;
import android.widget.ListView;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.ListIterator;

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
                Intent addChartIntent = new Intent(getApplicationContext(), AddChart.class);
                addChartIntent.putExtra("icao", icao);
                startActivity(addChartIntent);
            }
        });

        populateListView();

    }

    @Override
    protected void onResume(){
        super.onResume();
        populateListView();
    }

    private void populateListView(){
        DBHandler db = new DBHandler(this);

        //Get airports list
        final List<Chart> chartsList = db.getChartsList(this.icao);

        //Convert to String List
        List<String> chartsStringList = new ArrayList<>();
        for(Chart chart: chartsList){
            chartsStringList.add(chart.name);
        }

        Log.d("ChartsList", chartsList.toString());
        final String[] charts = new String[chartsStringList.size()];
        //Convert List to String Array
        chartsStringList.toArray(charts);

        ListAdapter airportsListAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, charts);
        chartsListView.setAdapter(airportsListAdapter);

        chartsListView.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
                int chartId = chartsList.get(position).id;
                Log.d("ChartId", String.valueOf(chartId));
            }
        });

    }
}
