package com.daniyaalkhan.imgmap;

import android.app.Application;
import android.content.Intent;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.text.InputFilter;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;

public class AddAirport extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_add_airport);

        final EditText airportICAOText = findViewById(R.id.airportICAO);

        final Button addAirportButton = findViewById(R.id.addAirport);

        airportICAOText.setFilters(new InputFilter[]{new InputFilter.AllCaps(), new InputFilter.LengthFilter(4)});

        addAirportButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {

                //Check if airport ICAO is 4 characters
                if(airportICAOText.getText().length()!=4)
                    airportICAOText.setError("Enter a valid ICAO code");
                else{

                    DBHandler db = new DBHandler(v.getContext());
                    String icao = airportICAOText.getText().toString();

                    if(db.getAirportExists(icao))
                        airportICAOText.setError("Airport already exists in your list");
                    else {

                        long id = db.addAirport(airportICAOText.getText().toString());

                        //Log.d("InsertAt", String.valueOf(check));

                        Toast.makeText(v.getContext(), "Added "+icao+" to database", Toast.LENGTH_SHORT).show();

                        Intent chartsPage = new Intent(getApplicationContext(), Charts.class);
                        chartsPage.putExtra("icao", icao);
                        startActivity(chartsPage);

                    }

                }

            }
        });
    }
}
