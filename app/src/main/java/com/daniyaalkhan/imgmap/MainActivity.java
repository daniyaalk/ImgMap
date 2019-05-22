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
import java.util.List;

public class MainActivity extends AppCompatActivity {

    private ListView airportsListView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        this.airportsListView = findViewById(R.id.airportsList);

        Button addAirportButton = findViewById(R.id.addAirport);
        addAirportButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent addAirportIntent = new Intent(getApplicationContext(), AddAirport.class);
                startActivity(addAirportIntent);
            }
        });

        populateListView();

    }

    @Override
    public void onResume(){

        super.onResume();
        populateListView();

    }

    private void populateListView(){
        DBHandler db = new DBHandler(this);

        //Get airports list
        List<String> airportsList = db.getAirportsList();
        final String[] airports = new String[airportsList.size()];
        //Convert List to String Array
        airportsList.toArray(airports);

        ListAdapter airportsListAdapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, airports);
        Arrays.sort(airports);
        airportsListView.setAdapter(airportsListAdapter);

        airportsListView.setOnItemClickListener(new AdapterView.OnItemClickListener(){
            public void onItemClick(AdapterView<?>parent, View view, int position, long id){
                Log.i("Test", position+" "+id);

                Intent openAirport = new Intent(getApplicationContext(), Charts.class);
                openAirport.putExtra("icao", airports[position]);
                startActivity(openAirport);

            }
        });
    }
}
