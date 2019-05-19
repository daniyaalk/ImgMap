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

import java.util.Arrays;

public class MainActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        Button addAirportButton = findViewById(R.id.addAirport);
        addAirportButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent addAirportIntent = new Intent(getApplicationContext(), AddAirport.class);
                startActivity(addAirportIntent);
            }
        });

        final String[] airports = {"VIDP", "VAAU"};
        ListAdapter airportsList = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, airports);
        Arrays.sort(airports);
        ListView airportsListView = findViewById(R.id.airportsList);
        airportsListView.setAdapter(airportsList);

        airportsListView.setOnItemClickListener(new AdapterView.OnItemClickListener(){
            public void onItemClick(AdapterView<?>parent, View view, int position, long id){
                Log.i("Test", String.valueOf(position)+" "+id);

                Intent openAirport = new Intent(getApplicationContext(), ChartActivity.class);
                openAirport.putExtra("icao", airports[position]);
                startActivity(openAirport);

            }
        });
    }
}
